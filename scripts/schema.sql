-- IGNITE メモリデータベース スキーマ
-- タイムスタンプは JST (UTC+9) で記録
PRAGMA user_version = 1;

-- メモリテーブル（全エージェント共通：学習・決定・観察・エラーを記録）
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent TEXT NOT NULL,
    type TEXT NOT NULL,         -- 'decision', 'learning', 'observation', 'error', 'message_sent', 'message_received'
    content TEXT NOT NULL,
    context TEXT,
    task_id TEXT,
    timestamp DATETIME DEFAULT (datetime('now', '+9 hours'))
);

-- タスク状態テーブル（進行中タスクの追跡）
CREATE TABLE IF NOT EXISTS tasks (
    task_id TEXT PRIMARY KEY,
    assigned_to TEXT NOT NULL,
    delegated_by TEXT,
    status TEXT DEFAULT 'queued',
    title TEXT,
    started_at DATETIME,
    completed_at DATETIME
);

-- エージェント状態テーブル（再起動復元用）
CREATE TABLE IF NOT EXISTS agent_states (
    agent TEXT PRIMARY KEY,
    status TEXT,
    current_task_id TEXT,
    last_active DATETIME,
    summary TEXT
);

-- Strategist 戦略状態テーブル（strategist_pending.yaml の代替）
CREATE TABLE IF NOT EXISTS strategist_state (
    request_id TEXT PRIMARY KEY,
    goal TEXT NOT NULL,
    status TEXT NOT NULL,       -- 'drafting', 'pending_reviews', 'completed'
    created_at DATETIME,
    draft_strategy TEXT,        -- JSON: 戦略ドラフト
    reviews TEXT                -- JSON: 各Sub-Leaderのレビュー状態
);

-- インデックス
CREATE INDEX IF NOT EXISTS idx_memories_agent_type ON memories(agent, type, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_memories_task ON memories(task_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status, assigned_to);
CREATE INDEX IF NOT EXISTS idx_strategist_status ON strategist_state(status);
