# shellcheck shell=bash
# lib/cmd_init.sh - initコマンド（ワークスペース設定の初期化）
[[ -n "${__LIB_CMD_INIT_LOADED:-}" ]] && return; __LIB_CMD_INIT_LOADED=1

# =============================================================================
# init コマンド - ワークスペース固有の .ignite/ 設定を初期化
# =============================================================================
cmd_init() {
    local target_dir=""
    local force=false
    local minimal=false

    # オプション解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w|--workspace)
                target_dir="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            --minimal)
                minimal=true
                shift
                ;;
            -h|--help)
                _cmd_init_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                _cmd_init_help
                exit 1
                ;;
            *)
                # 位置引数としてディレクトリを受け取る
                if [[ -z "$target_dir" ]]; then
                    target_dir="$1"
                fi
                shift
                ;;
        esac
    done

    # ディレクトリ解決
    if [[ -z "$target_dir" ]]; then
        target_dir="$(pwd)"
    fi
    # 相対パスを絶対パスに変換
    if [[ ! "$target_dir" = /* ]]; then
        target_dir="$(cd "$target_dir" 2>/dev/null && pwd)" || {
            print_error "ディレクトリが存在しません: $target_dir"
            exit 1
        }
    fi

    local ignite_dir="${target_dir}/.ignite"

    print_header "IGNITE ワークスペース初期化"
    echo ""
    echo -e "${BLUE}対象ディレクトリ:${NC} $target_dir"
    echo -e "${BLUE}.ignite ディレクトリ:${NC} $ignite_dir"
    echo ""

    # 既存チェック
    if [[ -d "$ignite_dir" ]] && [[ "$force" == false ]]; then
        print_warning ".ignite/ ディレクトリは既に存在します: $ignite_dir"
        echo -e "上書きする場合は ${YELLOW}--force${NC} オプションを使用してください。"
        exit 1
    fi

    # .ignite/ ディレクトリ作成
    print_info ".ignite/ ディレクトリを作成中..."
    mkdir -p "$ignite_dir"

    # .gitignore 生成（.ignite/ 内）
    cat > "$ignite_dir/.gitignore" <<'GITIGNORE'
# IGNITE workspace config
# credentials はグローバル設定（~/.config/ignite/）で管理するため除外不要
# ワークスペース設定はリポジトリにコミット可能

# ローカルのみの設定（必要に応じてコメント解除）
# system.yaml
# github-watcher.yaml
GITIGNORE
    print_success ".gitignore を生成しました"

    # テンプレート設定ファイルのコピー
    if [[ "$minimal" == true ]]; then
        # --minimal: system.yaml のみ
        _copy_config_template "system.yaml" "$ignite_dir"
    else
        # 通常: github-app.yaml 以外の全設定ファイルをコピー
        _copy_config_template "system.yaml" "$ignite_dir"
        _copy_config_template "characters.yaml" "$ignite_dir"
        _copy_config_template "pricing.yaml" "$ignite_dir"

        # github-watcher.yaml は example があればコピー
        if [[ -f "$IGNITE_CONFIG_DIR/github-watcher.yaml" ]]; then
            _copy_config_template "github-watcher.yaml" "$ignite_dir"
        elif [[ -f "$IGNITE_CONFIG_DIR/github-watcher.yaml.example" ]]; then
            cp "$IGNITE_CONFIG_DIR/github-watcher.yaml.example" "$ignite_dir/github-watcher.yaml"
            print_success "github-watcher.yaml をexampleからコピーしました"
        fi
    fi

    # 標準ディレクトリ作成
    print_info "標準ディレクトリを作成中..."
    mkdir -p "$target_dir/workspace"/{queue,context,logs,state,repos}
    print_success "workspace/ ディレクトリを作成しました"

    # 完了メッセージ
    echo ""
    print_header "初期化完了"
    echo ""
    echo "作成された構造:"
    echo "  ${target_dir}/"
    echo "  ├── .ignite/"
    echo "  │   ├── .gitignore"
    echo "  │   ├── system.yaml"
    if [[ "$minimal" == false ]]; then
        echo "  │   ├── characters.yaml"
        echo "  │   └── pricing.yaml"
    fi
    echo "  └── workspace/"
    echo "      ├── queue/"
    echo "      ├── context/"
    echo "      ├── logs/"
    echo "      ├── state/"
    echo "      └── repos/"
    echo ""
    echo -e "${YELLOW}注意:${NC} github-app.yaml（credentials）はグローバル設定"
    echo -e "（${CYAN}~/.config/ignite/github-app.yaml${NC}）で管理されます。"
    echo -e "ワークスペースにはコピーされません（セキュリティ保護）。"
    echo ""
    echo "次のステップ:"
    echo -e "  1. 設定を編集: ${YELLOW}vi ${ignite_dir}/system.yaml${NC}"
    echo -e "  2. 起動: ${YELLOW}ignite start -w ${target_dir}/workspace${NC}"
}

# _copy_config_template - グローバル設定からワークスペースにコピー
# Usage: _copy_config_template <filename> <dest_dir>
_copy_config_template() {
    local filename="$1"
    local dest_dir="$2"

    # github-app.yaml は絶対にコピーしない
    if [[ "$filename" == "github-app.yaml" ]]; then
        return 0
    fi

    if [[ -f "$IGNITE_CONFIG_DIR/$filename" ]]; then
        cp "$IGNITE_CONFIG_DIR/$filename" "$dest_dir/$filename"
        print_success "$filename をコピーしました"
    else
        print_warning "$filename がグローバル設定に見つかりません（スキップ）"
    fi
}

# _cmd_init_help - init コマンドのヘルプ表示
_cmd_init_help() {
    echo "使用方法: ignite init [OPTIONS] [WORKSPACE_DIR]"
    echo ""
    echo "ワークスペース固有の .ignite/ 設定ディレクトリを初期化します。"
    echo "グローバル設定（~/.config/ignite/）をテンプレートとしてコピーし、"
    echo "プロジェクトごとにカスタマイズ可能にします。"
    echo ""
    echo "オプション:"
    echo "  -w, --workspace <dir>   初期化するディレクトリを指定"
    echo "  -f, --force             既存の .ignite/ を上書き"
    echo "  --minimal               system.yaml のみコピー（最小構成）"
    echo "  -h, --help              この使い方を表示"
    echo ""
    echo "例:"
    echo "  ignite init                    # カレントディレクトリに初期化"
    echo "  ignite init /path/to/project   # 指定ディレクトリに初期化"
    echo "  ignite init --minimal          # 最小構成で初期化"
    echo "  ignite init -f                 # 既存設定を上書き"
    echo ""
    echo "設計:"
    echo "  - .ignite/ 内の設定はグローバル設定より優先されます"
    echo "  - github-app.yaml（credentials）はセキュリティ上、グローバル固定です"
    echo "  - .ignite/ はリポジトリにコミット可能です（チーム共有用）"
}
