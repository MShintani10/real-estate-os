const { Pool } = require("pg");

let pool = null;

function getDatabaseUrl() {
    return process.env.DATABASE_URL || process.env.POSTGRES_URL || "";
}

function getPool() {
    if (pool) {
        return pool;
    }

    const connectionString = getDatabaseUrl();
    if (!connectionString) {
        return null;
    }

    pool = new Pool({ connectionString });
    return pool;
}

async function ensureSchema() {
    const db = getPool();
    if (!db) {
        return false;
    }

    await db.query(`
        CREATE TABLE IF NOT EXISTS calendar_events (
            id BIGSERIAL PRIMARY KEY,
            title TEXT NOT NULL,
            event_date DATE NOT NULL,
            start_time TIME,
            end_time TIME,
            notes TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    `);

    await db.query(`
        CREATE INDEX IF NOT EXISTS idx_calendar_events_event_date
            ON calendar_events (event_date)
    `);

    return true;
}

module.exports = {
    getPool,
    ensureSchema
};
