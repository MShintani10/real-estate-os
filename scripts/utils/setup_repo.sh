#!/opt/homebrew/bin/bash
# 外部リポジトリのセットアップスクリプト
# clone, ブランチ作成, 作業ディレクトリ管理
#
# 使用方法:
#   ./scripts/utils/setup_repo.sh clone <owner/repo> [base_branch]
#   ./scripts/utils/setup_repo.sh branch <repo_path> <issue_number> [base_branch]
#   ./scripts/utils/setup_repo.sh path <owner/repo>
#   ./scripts/utils/setup_repo.sh default-branch <owner/repo>
#   ./scripts/utils/setup_repo.sh bootstrap-app <target_dir> [--force]

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -n "${WORKSPACE_DIR:-}" ]] && setup_workspace_config "$WORKSPACE_DIR"

# Bot Token / GitHub API / Git操作ラッパーの読み込み
source "${SCRIPT_DIR}/github_helpers.sh"

REPOS_DIR="${IGNITE_RUNTIME_DIR:-${WORKSPACE_DIR:-$PROJECT_ROOT/workspace}}/repos"

# =============================================================================
# ヘルプ
# =============================================================================

show_help() {
    cat << 'EOF'
リポジトリ管理スクリプト

使用方法:
  ./scripts/utils/setup_repo.sh clone <owner/repo> [base_branch]
  ./scripts/utils/setup_repo.sh branch <repo_path> <issue_number> [base_branch]
  ./scripts/utils/setup_repo.sh path <owner/repo>
  ./scripts/utils/setup_repo.sh default-branch <owner/repo>
  ./scripts/utils/setup_repo.sh base-branch <owner/repo>
  ./scripts/utils/setup_repo.sh bootstrap-app <target_dir> [--force]

コマンド:
  clone <owner/repo> [base_branch]
      リポジトリをclone（または更新）します。
      base_branch を省略した場合はリポジトリのデフォルトブランチを使用。

  branch <repo_path> <issue_number> [base_branch]
      Issue用のブランチを作成します。
      ブランチ名は ignite/issue-{issue_number} になります。

  path <owner/repo>
      リポジトリのローカルパスを取得します。

  default-branch <owner/repo>
      リポジトリのデフォルトブランチを取得します（GitHub API使用）。

  base-branch <owner/repo>
      設定ファイルからベースブランチを取得します。
      設定がない場合はリポジトリのデフォルトブランチを使用。

  bootstrap-app <target_dir> [--force]
      React + API + PostgreSQL + CI 構成の基盤リポジトリを生成します。
      --force を指定すると既存ファイルを上書きします。

環境変数:
  WORKSPACE_DIR    ワークスペースディレクトリ（デフォルト: workspace）

例:
  # リポジトリをclone
  ./scripts/utils/setup_repo.sh clone owner/repo

  # 特定のブランチを指定してclone
  ./scripts/utils/setup_repo.sh clone owner/repo develop

  # パス取得
  REPO_PATH=$(./scripts/utils/setup_repo.sh path owner/repo)
  echo $REPO_PATH  # workspace/repos/owner_repo

  # Issue用ブランチ作成
  ./scripts/utils/setup_repo.sh branch "$REPO_PATH" 123

  # 公開アプリ基盤を作成
  ./scripts/utils/setup_repo.sh bootstrap-app /tmp/my-app

  # 作業
  cd "$REPO_PATH"
  # ... 編集 ...

  # PR作成
  ./scripts/utils/create_pr.sh 123 --repo owner/repo
EOF
}

# =============================================================================
# ユーティリティ関数
# =============================================================================

# リポジトリのデフォルトブランチを取得
get_default_branch() {
    local repo="$1"
    local response
    response=$(github_api_get "$repo" "/repos/${repo}" 2>/dev/null) || true
    if [[ -n "$response" ]]; then
        local branch
        branch=$(printf '%s' "$response" | _json_get '.default_branch')
        if [[ -n "$branch" && "$branch" != "null" ]]; then
            echo "$branch"
            return 0
        fi
    fi
    echo "main"
}

# 設定ファイルからベースブランチを取得（なければデフォルトブランチ）
get_base_branch() {
    local repo="$1"
    local config_file="${IGNITE_CONFIG_DIR}/github-watcher.yaml"

    if [[ -f "$config_file" ]]; then
        # リポジトリ別の設定を取得
        # repositories セクションから repo に対応する base_branch を探す
        local configured_branch=""

        # YAMLのパース（簡易版）
        local in_repo_section=false
        local found_repo=false
        while IFS= read -r line; do
            # repositories: セクションに入ったか確認
            if [[ "$line" =~ ^[[:space:]]*repositories: ]]; then
                in_repo_section=true
                continue
            fi

            if [[ "$in_repo_section" == true ]]; then
                # 新しいリポジトリエントリ
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*repo:[[:space:]]*\"?([^\"]+)\"? ]]; then
                    local current_repo="${BASH_REMATCH[1]}"
                    current_repo=$(echo "$current_repo" | tr -d '"' | tr -d "'" | xargs)
                    if [[ "$current_repo" == "$repo" ]]; then
                        found_repo=true
                    else
                        found_repo=false
                    fi
                    continue
                fi

                # base_branch 設定
                if [[ "$found_repo" == true ]] && [[ "$line" =~ ^[[:space:]]*base_branch:[[:space:]]*\"?([^\"]+)\"? ]]; then
                    configured_branch="${BASH_REMATCH[1]}"
                    configured_branch=$(echo "$configured_branch" | tr -d '"' | tr -d "'" | xargs)
                    break
                fi

                # 別のトップレベルセクションに移動したら終了
                if [[ "$line" =~ ^[a-z]+: ]]; then
                    in_repo_section=false
                fi
            fi
        done < "$config_file"

        if [[ -n "$configured_branch" ]]; then
            echo "$configured_branch"
            return
        fi
    fi

    # デフォルトブランチを取得
    get_default_branch "$repo"
}

# リポジトリ名からローカルパスを生成
# IGNITE_WORKER_ID が設定されている場合は per-IGNITIAN パスを返す
repo_to_path() {
    local repo="$1"
    # owner/repo → owner_repo
    local repo_name
    repo_name=$(echo "$repo" | tr '/' '_')
    if [[ -n "${IGNITE_WORKER_ID:-}" ]]; then
        echo "$REPOS_DIR/${repo_name}_ignitian_${IGNITE_WORKER_ID}"
    else
        echo "$REPOS_DIR/$repo_name"
    fi
}

# =============================================================================
# リポジトリ操作
# =============================================================================

# リポジトリをclone（または更新）
setup_repo() {
    local repo="$1"
    local branch="${2:-}"

    # ベースブランチを決定
    if [[ -z "$branch" ]]; then
        branch=$(get_base_branch "$repo")
    fi

    local repo_path
    repo_path=$(repo_to_path "$repo")

    mkdir -p "$REPOS_DIR"

    if [[ -d "$repo_path/.git" ]]; then
        log_info "リポジトリが既に存在します。更新中..."
        cd "$repo_path"
        safe_git_fetch origin
        git checkout "$branch" 2>/dev/null || git checkout -b "$branch" "origin/$branch"
        safe_git_pull origin "$branch" || log_warn "pull に失敗しました（ローカル変更がある可能性）"
    else
        # per-IGNITIAN clone: primary clone が存在すればローカルから高速clone
        local repo_name
        repo_name=$(echo "$repo" | tr '/' '_')
        local primary_path="$REPOS_DIR/$repo_name"
        if [[ -n "${IGNITE_WORKER_ID:-}" ]] && [[ -d "$primary_path/.git" ]]; then
            log_info "primary clone からローカルclone: $repo (worker ${IGNITE_WORKER_ID})"
            git clone --no-hardlinks --branch "$branch" "$primary_path" "$repo_path"
            # origin URL をGitHubに再設定（ローカルcloneだとoriginがローカルパスになるため）
            git -C "$repo_path" remote set-url origin "https://github.com/${repo}.git"
        else
            log_info "リポジトリをclone中: $repo"
            local auth_token=""
            auth_token=$(get_auth_token "$repo") || true
            if [[ -z "$auth_token" ]]; then
                _print_auth_error "$repo"
                return 1
            fi
            if [[ "$AUTH_TOKEN_SOURCE" == "pat" ]]; then
                log_warn "GitHub App Token取得失敗のため、PATでcloneします。"
            fi
            local clone_url
            clone_url="$(get_github_base_url)/${repo}.git"
            local basic
            basic=$(_build_basic_auth "$auth_token")
            local host
            host=$(get_github_hostname)
            git -c "http.https://${host}/.extraHeader=Authorization: Basic ${basic}" \
                clone --branch "$branch" "$clone_url" "$repo_path"
        fi
        cd "$repo_path"
    fi

    log_success "リポジトリのセットアップ完了: $repo_path"
    echo "$repo_path"
}

# Issue用のブランチを作成
create_issue_branch() {
    local repo_path="$1"
    local issue_number="$2"
    local base_branch="${3:-}"

    # ベースブランチが未指定の場合はリポジトリのデフォルトを取得
    if [[ -z "$base_branch" ]]; then
        cd "$repo_path"
        # リモートからデフォルトブランチを取得
        base_branch=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
        if [[ -z "$base_branch" ]]; then
            base_branch="main"
        fi
    fi

    local branch_name="ignite/issue-${issue_number}"

    cd "$repo_path"
    safe_git_fetch origin

    # ベースブランチを更新
    git checkout "$base_branch" 2>/dev/null || git checkout -b "$base_branch" "origin/$base_branch"
    safe_git_pull origin "$base_branch" || log_warn "pull に失敗しました"

    # ブランチが既に存在するか確認
    if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
        log_warn "ブランチが既に存在します: $branch_name"
        git checkout "$branch_name"
        # リモートの変更を取り込む
        safe_git_pull origin "$branch_name" 2>/dev/null || true
    else
        log_info "ブランチを作成中: $branch_name"
        git checkout -b "$branch_name"
    fi

    log_success "ブランチ作成完了: $branch_name"
    echo "$branch_name"
}

# リポジトリのパスを取得
get_repo_path() {
    local repo="$1"
    repo_to_path "$repo"
}

# ファイル書き込み（必要に応じて上書き）
write_template_file() {
    local file_path="$1"
    local force_overwrite="$2"

    if [[ "$force_overwrite" != "true" ]] && [[ -f "$file_path" ]]; then
        log_warn "既存ファイルをスキップ: $file_path"
        return 0
    fi

    mkdir -p "$(dirname "$file_path")"
    cat > "$file_path"
}

# 公開可能なアプリ基盤を生成
bootstrap_app_repo() {
    local target_dir="${1:-}"
    shift || true

    local force_overwrite="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force_overwrite="true"
                ;;
            *)
                log_error "Unknown option for bootstrap-app: $1"
                return 1
                ;;
        esac
        shift
    done

    if [[ -z "$target_dir" ]]; then
        log_error "bootstrap-app には <target_dir> が必要です"
        return 1
    fi

    mkdir -p "$target_dir"
    if [[ "$force_overwrite" != "true" ]] && find "$target_dir" -mindepth 1 -print -quit | grep -q .; then
        log_error "target_dir が空ではありません: $target_dir"
        log_info "--force を付けると上書きできます"
        return 1
    fi

    mkdir -p \
        "$target_dir/apps/web/src" \
        "$target_dir/apps/api/src" \
        "$target_dir/apps/api/tests" \
        "$target_dir/db/init" \
        "$target_dir/.github/workflows"

    write_template_file "$target_dir/.gitignore" "$force_overwrite" <<'EOF'
node_modules/
dist/
coverage/
.env
.env.local
.DS_Store
EOF

    write_template_file "$target_dir/.env.example" "$force_overwrite" <<'EOF'
POSTGRES_USER=app
POSTGRES_PASSWORD=app
POSTGRES_DB=app
DATABASE_URL=postgres://app:app@db:5432/app
VITE_API_BASE_URL=http://localhost:3001
EOF

    write_template_file "$target_dir/package.json" "$force_overwrite" <<'EOF'
{
  "name": "ignite-app-foundation",
  "private": true,
  "workspaces": [
    "apps/*"
  ],
  "scripts": {
    "build": "npm run build -w apps/api && npm run build -w apps/web",
    "test": "npm run test -w apps/api && npm run test -w apps/web",
    "lint": "npm run lint -w apps/api && npm run lint -w apps/web"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
EOF

    write_template_file "$target_dir/docker-compose.yml" "$force_overwrite" <<'EOF'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
      POSTGRES_DB: ${POSTGRES_DB:-app}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./db/init:/docker-entrypoint-initdb.d:ro

  api:
    build:
      context: .
      dockerfile: apps/api/Dockerfile
    environment:
      DATABASE_URL: ${DATABASE_URL:-postgres://app:app@db:5432/app}
      PORT: 3001
      NODE_ENV: development
    ports:
      - "3001:3001"
    depends_on:
      - db

  web:
    build:
      context: .
      dockerfile: apps/web/Dockerfile
    environment:
      VITE_API_BASE_URL: ${VITE_API_BASE_URL:-http://localhost:3001}
    ports:
      - "5173:80"
    depends_on:
      - api

volumes:
  postgres_data:
EOF

    write_template_file "$target_dir/README.md" "$force_overwrite" <<'EOF'
# App Foundation (React + API + PostgreSQL)

IGNITEで並列実装を回しやすい、公開前提の土台リポジトリです。

## Stack
- Frontend: React + Vite
- Backend: Node.js (Express)
- DB: PostgreSQL 16
- CI: GitHub Actions + `shadowci.yml` テンプレート

## Quick Start
```bash
cp .env.example .env
docker compose up --build
```

- Web: http://localhost:5173
- API: http://localhost:3001/healthz
- PostgreSQL: localhost:5432

## AI Agent Parallel Plan (Example)
1. Strategist: 要件分解と優先順位付け
2. Architect: API契約とDB設計
3. Coordinator: 実装タスクを複数ワーカーに配布
4. Evaluator: テスト・品質評価
5. Innovator: UX改善・差別化案
EOF

    write_template_file "$target_dir/shadowci.yml" "$force_overwrite" <<'EOF'
version: 1
pipeline:
  - name: install
    run: npm install
  - name: lint
    run: npm run lint
  - name: test
    run: npm run test
  - name: build
    run: npm run build
EOF

    write_template_file "$target_dir/.github/workflows/ci.yml" "$force_overwrite" <<'EOF'
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm install
      - run: npm run lint
      - run: npm run test
      - run: npm run build
EOF

    write_template_file "$target_dir/apps/api/package.json" "$force_overwrite" <<'EOF'
{
  "name": "@app/api",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "node --watch src/index.js",
    "start": "node src/index.js",
    "build": "echo \"api build: no-op\"",
    "lint": "node -e \"console.log('api lint: no-op')\"",
    "test": "node --test tests/health.test.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "pg": "^8.12.0"
  }
}
EOF

    write_template_file "$target_dir/apps/api/src/index.js" "$force_overwrite" <<'EOF'
import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import pg from "pg";

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const port = process.env.PORT || 3001;
const databaseUrl = process.env.DATABASE_URL || "";

app.get("/healthz", async (_req, res) => {
    if (!databaseUrl) {
        return res.status(200).json({ status: "ok", db: "skipped" });
    }

    const client = new pg.Client({ connectionString: databaseUrl });
    try {
        await client.connect();
        await client.query("SELECT 1");
        return res.status(200).json({ status: "ok", db: "ok" });
    } catch (_error) {
        return res.status(503).json({ status: "degraded", db: "error" });
    } finally {
        await client.end().catch(() => {});
    }
});

app.get("/api/version", (_req, res) => {
    res.json({ name: "@app/api", version: "0.1.0" });
});

app.listen(port, () => {
    console.log(`api listening on ${port}`);
});
EOF

    write_template_file "$target_dir/apps/api/tests/health.test.js" "$force_overwrite" <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";

test("placeholder", () => {
    assert.equal(1 + 1, 2);
});
EOF

    write_template_file "$target_dir/apps/api/Dockerfile" "$force_overwrite" <<'EOF'
FROM node:20-alpine
WORKDIR /app

COPY package*.json ./
COPY apps/api/package*.json apps/api/
RUN npm install

COPY apps/api apps/api
WORKDIR /app/apps/api
EXPOSE 3001

CMD ["npm", "run", "start"]
EOF

    write_template_file "$target_dir/apps/web/package.json" "$force_overwrite" <<'EOF'
{
  "name": "@app/web",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "lint": "node -e \"console.log('web lint: no-op')\"",
    "test": "node -e \"console.log('web test: no-op')\""
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "vite": "^5.4.0"
  }
}
EOF

    write_template_file "$target_dir/apps/web/index.html" "$force_overwrite" <<'EOF'
<!doctype html>
<html lang="ja">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>App Foundation</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

    write_template_file "$target_dir/apps/web/src/main.jsx" "$force_overwrite" <<'EOF'
import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";

createRoot(document.getElementById("root")).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
);
EOF

    write_template_file "$target_dir/apps/web/src/App.jsx" "$force_overwrite" <<'EOF'
import { useEffect, useState } from "react";

export function App() {
    const [health, setHealth] = useState("loading");
    const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:3001";

    useEffect(() => {
        fetch(`${apiBaseUrl}/healthz`)
            .then((res) => res.json())
            .then((json) => setHealth(json.status || "unknown"))
            .catch(() => setHealth("error"));
    }, [apiBaseUrl]);

    return (
        <main style={{ fontFamily: "sans-serif", padding: "24px" }}>
            <h1>App Foundation</h1>
            <p>React + API + PostgreSQL</p>
            <p>API health: {health}</p>
        </main>
    );
}
EOF

    write_template_file "$target_dir/apps/web/Dockerfile" "$force_overwrite" <<'EOF'
FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
COPY apps/web/package*.json apps/web/
RUN npm install

COPY apps/web apps/web
WORKDIR /app/apps/web
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
EXPOSE 80
EOF

    write_template_file "$target_dir/db/init/001_init.sql" "$force_overwrite" <<'EOF'
CREATE TABLE IF NOT EXISTS app_users (
    id BIGSERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
EOF

    if [[ ! -d "$target_dir/.git" ]]; then
        git init "$target_dir" >/dev/null 2>&1 || true
    fi

    log_success "アプリ基盤の生成完了: $target_dir"
    echo "$target_dir"
}

# =============================================================================
# メイン
# =============================================================================

main() {
    local action="${1:-}"
    shift || true

    case "$action" in
        clone|setup)
            setup_repo "$@"
            ;;
        branch)
            create_issue_branch "$@"
            ;;
        path)
            get_repo_path "$@"
            ;;
        default-branch)
            get_default_branch "$@"
            ;;
        base-branch)
            get_base_branch "$@"
            ;;
        bootstrap-app)
            bootstrap_app_repo "$@"
            ;;
        -h|--help|help)
            show_help
            ;;
        "")
            log_error "アクションを指定してください"
            echo ""
            show_help
            exit 1
            ;;
        *)
            log_error "Unknown action: $action"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
