#!/usr/bin/env bats
# test_workspace_config.bats - ワークスペース設定(.ignite/)の統合テスト
# Issue #214 Phase 2: 20テストケース

load test_helper

setup() {
    setup_temp_dir

    # core.sh に必要な最小限のグローバル設定を準備
    export IGNITE_CONFIG_DIR="$TEST_TEMP_DIR/global_config"
    mkdir -p "$IGNITE_CONFIG_DIR"

    # グローバル system.yaml
    cat > "$IGNITE_CONFIG_DIR/system.yaml" <<'YAML'
tmux:
  window_name: ignite
delays:
  leader_startup: 3
  claude_startup: 8
  leader_init: 10
  agent_stabilize: 2
  agent_retry_wait: 3
  process_cleanup: 1
  session_create: 1
  permission_accept: 1
  prompt_send: 1
defaults:
  message_priority: normal
  task_timeout: 300
  worker_count: 3
YAML

    # グローバル github-watcher.yaml
    cat > "$IGNITE_CONFIG_DIR/github-watcher.yaml" <<'YAML'
watcher:
  repositories:
    - repo: owner/global-repo
  interval: 60
  events:
    issues: true
  ignore_bot: true
enabled: true
access_control:
  enabled: false
logging:
  level: info
YAML

    # core.sh をソース（resolve_config, setup_workspace_config を利用可能に）
    # shellcheck 回避: 必要な変数を事前設定
    export PROJECT_ROOT="$SCRIPTS_DIR/.."
    export WORKSPACE_DIR="$TEST_TEMP_DIR/workspace"
    export WORKSPACE_CONFIG_DIR=""
    mkdir -p "$WORKSPACE_DIR"

    source "$SCRIPTS_DIR/lib/core.sh"
    source "$SCRIPTS_DIR/lib/yaml_utils.sh"
    source "$SCRIPTS_DIR/lib/session.sh"
}

teardown() {
    cleanup_temp_dir
}

# =============================================================================
# TC-1〜TC-6: config 優先順位テスト
# =============================================================================

@test "TC-1: resolve_config - グローバルのみ → グローバルパスを返す" {
    WORKSPACE_CONFIG_DIR=""
    local result
    result=$(resolve_config "system.yaml")
    [[ "$result" == "$IGNITE_CONFIG_DIR/system.yaml" ]]
}

@test "TC-2: resolve_config - ワークスペース設定あり → ワークスペースを優先" {
    local ws_ignite="$TEST_TEMP_DIR/workspace/.ignite"
    mkdir -p "$ws_ignite"
    cat > "$ws_ignite/system.yaml" <<'YAML'
tmux:
  window_name: ws-ignite
delays:
  leader_startup: 5
  claude_startup: 10
  leader_init: 12
  agent_stabilize: 3
  agent_retry_wait: 4
  process_cleanup: 2
  session_create: 2
  permission_accept: 2
  prompt_send: 2
defaults:
  message_priority: high
  task_timeout: 600
  worker_count: 5
YAML
    WORKSPACE_CONFIG_DIR="$ws_ignite"
    local result
    result=$(resolve_config "system.yaml")
    [[ "$result" == "$ws_ignite/system.yaml" ]]
}

@test "TC-3: resolve_config - ワークスペースに無いファイル → グローバルにフォールバック" {
    local ws_ignite="$TEST_TEMP_DIR/workspace/.ignite"
    mkdir -p "$ws_ignite"
    # system.yaml のみワークスペースに配置（pricing.yaml は無い）
    touch "$ws_ignite/system.yaml"
    WORKSPACE_CONFIG_DIR="$ws_ignite"

    # pricing.yaml はグローバルにのみ存在
    touch "$IGNITE_CONFIG_DIR/pricing.yaml"
    local result
    result=$(resolve_config "pricing.yaml")
    [[ "$result" == "$IGNITE_CONFIG_DIR/pricing.yaml" ]]
}

@test "TC-4: resolve_config - github-app.yaml は常にグローバル" {
    local ws_ignite="$TEST_TEMP_DIR/workspace/.ignite"
    mkdir -p "$ws_ignite"
    # ワークスペースにも github-app.yaml を配置（不正な状態）
    echo "github_app: {}" > "$ws_ignite/github-app.yaml"
    # グローバルにも配置
    echo "github_app: {app_id: '12345'}" > "$IGNITE_CONFIG_DIR/github-app.yaml"
    WORKSPACE_CONFIG_DIR="$ws_ignite"

    local result
    result=$(resolve_config "github-app.yaml")
    # グローバルが返される（ワークスペースは無視）
    [[ "$result" == "$IGNITE_CONFIG_DIR/github-app.yaml" ]]
}

@test "TC-5: resolve_config - 両方に無いファイル → 終了コード1" {
    WORKSPACE_CONFIG_DIR=""
    run resolve_config "nonexistent.yaml"
    [[ "$status" -eq 1 ]]
}

@test "TC-6: resolve_config - WORKSPACE_CONFIG_DIR空文字 → グローバルのみ検索" {
    WORKSPACE_CONFIG_DIR=""
    touch "$IGNITE_CONFIG_DIR/characters.yaml"
    local result
    result=$(resolve_config "characters.yaml")
    [[ "$result" == "$IGNITE_CONFIG_DIR/characters.yaml" ]]
}

# =============================================================================
# TC-7〜TC-10: 後方互換性テスト
# =============================================================================

@test "TC-7: setup_workspace_config - .ignite/ なし → WORKSPACE_CONFIG_DIR空" {
    setup_workspace_config "$TEST_TEMP_DIR/workspace"
    [[ -z "$WORKSPACE_CONFIG_DIR" ]]
}

@test "TC-8: setup_workspace_config - .ignite/ あり → WORKSPACE_CONFIG_DIR設定" {
    mkdir -p "$TEST_TEMP_DIR/workspace/.ignite"
    setup_workspace_config "$TEST_TEMP_DIR/workspace"
    [[ "$WORKSPACE_CONFIG_DIR" == "$TEST_TEMP_DIR/workspace/.ignite" ]]
}

@test "TC-9: get_worker_count - グローバルのみ → グローバル値を返す" {
    WORKSPACE_CONFIG_DIR=""
    local count
    count=$(get_worker_count)
    [[ "$count" == "3" ]]
}

@test "TC-10: get_worker_count - ワークスペース優先 → ワークスペース値を返す" {
    local ws_ignite="$TEST_TEMP_DIR/workspace/.ignite"
    mkdir -p "$ws_ignite"
    cat > "$ws_ignite/system.yaml" <<'YAML'
tmux:
  window_name: ignite
delays:
  leader_startup: 3
  claude_startup: 8
  leader_init: 10
  agent_stabilize: 2
  agent_retry_wait: 3
  process_cleanup: 1
  session_create: 1
  permission_accept: 1
  prompt_send: 1
defaults:
  message_priority: normal
  task_timeout: 300
  worker_count: 7
YAML
    WORKSPACE_CONFIG_DIR="$ws_ignite"
    local count
    count=$(get_worker_count)
    [[ "$count" == "7" ]]
}

# =============================================================================
# TC-11〜TC-17: ignite init 入力バリデーション
# =============================================================================

@test "TC-11: cmd_init - .ignite/ 新規作成" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local target="$TEST_TEMP_DIR/init_test"
    mkdir -p "$target"

    cmd_init --minimal -w "$target"
    [[ -d "$target/.ignite" ]]
    [[ -f "$target/.ignite/.gitignore" ]]
}

@test "TC-12: cmd_init - .ignite/ 既存で --force なし → 終了コード1" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local target="$TEST_TEMP_DIR/init_existing"
    mkdir -p "$target/.ignite"

    run cmd_init -w "$target"
    [[ "$status" -eq 1 ]]
}

@test "TC-13: cmd_init - --force で既存を上書き" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local target="$TEST_TEMP_DIR/init_force"
    mkdir -p "$target/.ignite"
    echo "old" > "$target/.ignite/.gitignore"

    cmd_init --force --minimal -w "$target"
    [[ -f "$target/.ignite/.gitignore" ]]
    # 上書きされている（old ではない）
    ! grep -q "^old$" "$target/.ignite/.gitignore"
}

@test "TC-14: cmd_init - --minimal で system.yaml のみコピー" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local target="$TEST_TEMP_DIR/init_minimal"
    mkdir -p "$target"

    cmd_init --minimal -w "$target"
    [[ -f "$target/.ignite/system.yaml" ]]
    # characters.yaml は --minimal ではコピーされない
    [[ ! -f "$target/.ignite/characters.yaml" ]]
}

@test "TC-15: cmd_init - workspace/ サブディレクトリ作成" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local target="$TEST_TEMP_DIR/init_dirs"
    mkdir -p "$target"

    cmd_init --minimal -w "$target"
    [[ -d "$target/workspace/queue" ]]
    [[ -d "$target/workspace/context" ]]
    [[ -d "$target/workspace/logs" ]]
    [[ -d "$target/workspace/state" ]]
    [[ -d "$target/workspace/repos" ]]
}

@test "TC-16: cmd_init - github-app.yaml はコピーされない" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local target="$TEST_TEMP_DIR/init_no_creds"
    mkdir -p "$target"
    # グローバルに github-app.yaml を配置
    echo "github_app: {app_id: '12345'}" > "$IGNITE_CONFIG_DIR/github-app.yaml"

    cmd_init -w "$target"
    # github-app.yaml はワークスペースにコピーされない
    [[ ! -f "$target/.ignite/github-app.yaml" ]]
}

@test "TC-17: cmd_init --help → 終了コード0" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    run cmd_init --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"使用方法"* ]]
}

# =============================================================================
# TC-18〜TC-20: セキュリティテスト
# =============================================================================

@test "TC-18: validate_workspace_config - github-app.yaml 存在時に警告" {
    if ! command -v yq &>/dev/null; then
        skip "yq が未インストール"
    fi
    source "$SCRIPTS_DIR/lib/config_validator.sh"

    local ws_ignite="$TEST_TEMP_DIR/workspace/.ignite"
    mkdir -p "$ws_ignite"
    echo "github_app: {app_id: '12345'}" > "$ws_ignite/github-app.yaml"

    _VALIDATION_ERRORS=()
    _VALIDATION_WARNINGS=()
    validate_workspace_config "$TEST_TEMP_DIR/workspace"

    # 警告が1件以上出る
    [[ ${#_VALIDATION_WARNINGS[@]} -ge 1 ]]
    local found=false
    for w in "${_VALIDATION_WARNINGS[@]}"; do
        [[ "$w" == *"credentials"* ]] && found=true
    done
    [[ "$found" == true ]]
}

@test "TC-19: validate_workspace_config - .ignite/ なしでエラーなし" {
    if ! command -v yq &>/dev/null; then
        skip "yq が未インストール"
    fi
    source "$SCRIPTS_DIR/lib/config_validator.sh"

    _VALIDATION_ERRORS=()
    _VALIDATION_WARNINGS=()
    validate_workspace_config "$TEST_TEMP_DIR/workspace"

    [[ ${#_VALIDATION_ERRORS[@]} -eq 0 ]]
    [[ ${#_VALIDATION_WARNINGS[@]} -eq 0 ]]
}

@test "TC-20: _copy_config_template - github-app.yaml はスキップ" {
    source "$SCRIPTS_DIR/lib/cmd_init.sh"
    local dest="$TEST_TEMP_DIR/dest_dir"
    mkdir -p "$dest"
    echo "github_app: {app_id: '12345'}" > "$IGNITE_CONFIG_DIR/github-app.yaml"

    _copy_config_template "github-app.yaml" "$dest"
    # github-app.yaml はコピーされない
    [[ ! -f "$dest/github-app.yaml" ]]
}

# =============================================================================
# TC-21〜TC-23: setup_workspace() .ignite/ 自動検出テスト
# =============================================================================

@test "TC-21: setup_workspace - CWDに.ignite/あり → CWDがWORKSPACE_DIR" {
    local test_ws="$TEST_TEMP_DIR/ws_detect"
    mkdir -p "$test_ws/.ignite"
    WORKSPACE_DIR=""

    # CWDを一時的に変更して検出テスト
    pushd "$test_ws" > /dev/null
    setup_workspace 2>/dev/null
    popd > /dev/null

    [[ "$WORKSPACE_DIR" == "$test_ws" ]]
}

@test "TC-22: setup_workspace - CWDに.ignite/なし → DEFAULT_WORKSPACE_DIR" {
    local test_ws="$TEST_TEMP_DIR/ws_no_ignite"
    mkdir -p "$test_ws"
    WORKSPACE_DIR=""

    pushd "$test_ws" > /dev/null
    setup_workspace 2>/dev/null
    popd > /dev/null

    [[ "$WORKSPACE_DIR" == "$DEFAULT_WORKSPACE_DIR" ]]
}

@test "TC-23: setup_workspace - -w指定済み → 検出スキップ" {
    local test_ws="$TEST_TEMP_DIR/ws_explicit"
    mkdir -p "$test_ws/.ignite"
    WORKSPACE_DIR="/explicitly/set/path"

    pushd "$test_ws" > /dev/null
    setup_workspace 2>/dev/null
    popd > /dev/null

    # -w で指定された値がそのまま維持される
    [[ "$WORKSPACE_DIR" == "/explicitly/set/path" ]]
}
