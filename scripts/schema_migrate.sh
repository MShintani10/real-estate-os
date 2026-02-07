#!/bin/bash
# schema_migrate.sh - 冪等なスキーママイグレーション
# PRAGMA user_version でバージョンを管理し、必要な場合のみ実行
set -e
set -u

DB_PATH="${1:-${WORKSPACE_DIR:-workspace}/state/memory.db}"

if [[ ! -f "$DB_PATH" ]]; then
    echo "[schema_migrate] DB not found: $DB_PATH (skip)" >&2
    exit 0
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "[schema_migrate] sqlite3 not found (skip)" >&2
    exit 0
fi

CURRENT_VERSION=$(sqlite3 "$DB_PATH" "PRAGMA user_version;")

if [[ "$CURRENT_VERSION" -ge 2 ]]; then
    echo "[schema_migrate] Already at version $CURRENT_VERSION (skip)" >&2
    exit 0
fi

echo "[schema_migrate] Migrating from version $CURRENT_VERSION to 2..." >&2

sqlite3 "$DB_PATH" <<'SQL'
PRAGMA busy_timeout = 5000;

-- 新カラム追加（既に存在する場合はエラーを無視）
ALTER TABLE tasks ADD COLUMN repository TEXT;
ALTER TABLE tasks ADD COLUMN issue_number INTEGER;

-- 既存全行にデフォルトのリポジトリを設定
UPDATE tasks SET repository = 'myfinder/IGNITE' WHERE repository IS NULL;

-- パターン1,2: issue{N}_task_{M}, issue{N}_task{M}
-- パターン含む issue{N}p{P}_task_* (CASTが非数字で停止するため自動対応)
UPDATE tasks
  SET issue_number = CAST(substr(task_id, 6, instr(substr(task_id, 6), '_') - 1) AS INTEGER)
  WHERE task_id LIKE 'issue%' AND issue_number IS NULL;

-- パターン3: issue{N}r{R}_task_* (より正確な抽出で上書き)
UPDATE tasks
  SET issue_number = CAST(substr(task_id, 6, instr(substr(task_id, 6), 'r') - 1) AS INTEGER)
  WHERE task_id LIKE 'issue%r%';

-- パターン4: task_{M}_issue{N} (末尾からissue番号を抽出)
UPDATE tasks
  SET issue_number = CAST(substr(task_id, instr(task_id, '_issue') + 6) AS INTEGER)
  WHERE task_id LIKE 'task_%_issue%';

-- パターン5: task_{M} (issue番号なし → NULL のまま)
-- 何もしない（デフォルトがNULL）

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_tasks_repo ON tasks(repository, status);

-- バージョン更新
PRAGMA user_version = 2;
SQL

echo "[schema_migrate] Migration to version 2 completed successfully." >&2
