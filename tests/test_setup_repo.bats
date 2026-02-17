#!/usr/bin/env bats
# =============================================================================
# setup_repo.sh のテスト
# テスト対象: bootstrap-app
# =============================================================================

load 'test_helper'

setup() {
    setup_temp_dir
}

teardown() {
    cleanup_temp_dir
}

@test "bootstrap-app: React + API + PostgreSQL 基盤を生成できる" {
    local target="$TEST_TEMP_DIR/app-foundation"
    run "$UTILS_DIR/setup_repo.sh" bootstrap-app "$target"

    [[ "$status" -eq 0 ]]
    [[ -f "$target/package.json" ]]
    [[ -f "$target/docker-compose.yml" ]]
    [[ -f "$target/apps/web/src/App.jsx" ]]
    [[ -f "$target/apps/api/src/index.js" ]]
    [[ -f "$target/db/init/001_init.sql" ]]
    [[ -f "$target/shadowci.yml" ]]
}

@test "bootstrap-app: 非空ディレクトリには --force なしで失敗する" {
    local target="$TEST_TEMP_DIR/not-empty"
    mkdir -p "$target"
    echo "dummy" > "$target/README.md"

    run "$UTILS_DIR/setup_repo.sh" bootstrap-app "$target"

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"target_dir が空ではありません"* ]]
}

@test "bootstrap-app: --force で既存ファイルを上書きできる" {
    local target="$TEST_TEMP_DIR/force"
    mkdir -p "$target"
    echo "old" > "$target/README.md"

    run "$UTILS_DIR/setup_repo.sh" bootstrap-app "$target" --force

    [[ "$status" -eq 0 ]]
    grep -q "React + API + PostgreSQL" "$target/README.md"
}
