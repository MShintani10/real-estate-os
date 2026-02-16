#!/usr/bin/env bats
# test_comment_on_issue.bats - comment_on_issue.sh べき等性チェックテスト
#
# Issue #261: コメント重複投稿防止の検証

load test_helper

setup() {
    setup_temp_dir
    export WORKSPACE_DIR="$TEST_TEMP_DIR/workspace"
    export IGNITE_RUNTIME_DIR="$WORKSPACE_DIR"
    mkdir -p "$IGNITE_RUNTIME_DIR/state"

    # ログ関数スタブ
    log_info() { echo "INFO: $*" >&2; }
    log_warn() { echo "WARN: $*" >&2; }
    log_error() { echo "ERROR: $*" >&2; }
    export -f log_info log_warn log_error

    # get_auth_token スタブ（GitHub App優先の挙動を模倣）
    get_auth_token() { AUTH_TOKEN_SOURCE="github_app"; echo "ghs_fake_token_for_test"; }
    export -f get_auth_token

    # _print_auth_error スタブ
    _print_auth_error() { echo "ERROR: auth token missing" >&2; }
    export -f _print_auth_error

    # comment_on_issue.sh から _is_duplicate_comment と post_comment を抽出
    eval "$(sed -n '/_is_duplicate_comment()/,/^}/p' "$SCRIPTS_DIR/utils/comment_on_issue.sh")"
    eval "$(sed -n '/^post_comment()/,/^}/p' "$SCRIPTS_DIR/utils/comment_on_issue.sh")"
}

teardown() {
    cleanup_temp_dir
}

# =============================================================================
# ヘルパー: github_api モック
# モック関数内で外部変数を参照するため、ファイル経由でレスポンスを渡す
# =============================================================================

_mock_paginate_and_post() {
    local paginate_response="$1"
    # レスポンスをファイルに書き出し（export -f のサブシェルでも読める）
    printf '%s' "$paginate_response" > "$TEST_TEMP_DIR/paginate_response.json"
    export TEST_TEMP_DIR

    github_api_paginate() { cat "$TEST_TEMP_DIR/paginate_response.json"; }
    export -f github_api_paginate

    github_api_post() { echo "posted" > "$TEST_TEMP_DIR/post_called"; echo '{"id":999}'; }
    export -f github_api_post
}

_mock_paginate_error_and_post() {
    export TEST_TEMP_DIR

    github_api_paginate() { return 1; }
    export -f github_api_paginate

    github_api_post() { echo "posted" > "$TEST_TEMP_DIR/post_called"; echo '{"id":999}'; }
    export -f github_api_post
}

# =============================================================================
# テスト
# =============================================================================

@test "idempotency: 重複コメントが存在する場合スキップされる" {
    _mock_paginate_and_post '[{"body":"既存コメント"},{"body":"テストコメント本文"}]'

    run post_comment "test/repo" "123" "テストコメント本文" "false"

    [[ "$status" -eq 0 ]]
    # 重複検出時は投稿されないこと
    [[ ! -f "$TEST_TEMP_DIR/post_called" ]]
}

@test "idempotency: 重複なしの場合通常投稿される" {
    _mock_paginate_and_post '[{"body":"別のコメント"},{"body":"関係ないコメント"}]'

    run post_comment "test/repo" "123" "新規コメント" "false"

    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TEMP_DIR/post_called" ]]
}

@test "idempotency: コメント一覧取得エラー時は投稿を続行する" {
    _mock_paginate_error_and_post

    run post_comment "test/repo" "123" "投稿内容" "false"

    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TEMP_DIR/post_called" ]]
}

@test "idempotency: Bot名義での重複チェックがBot Tokenを使用する" {
    _mock_paginate_and_post '[{"body":"既にある"}]'

    run post_comment "test/repo" "123" "新しいコメント" "true"

    [[ "$status" -eq 0 ]]
    [[ -f "$TEST_TEMP_DIR/post_called" ]]
}

@test "idempotency: 前後の空白差異は吸収される" {
    _mock_paginate_and_post '[{"body":"  テストコメント  \n"}]'

    run post_comment "test/repo" "123" "テストコメント" "false"

    [[ "$status" -eq 0 ]]
    # 空白差異を吸収して重複と判定するため、投稿されない
    [[ ! -f "$TEST_TEMP_DIR/post_called" ]]
}
