import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import pg from "pg";

dotenv.config();

const app = express();
const port = process.env.PORT || 3001;
const databaseUrl = process.env.DATABASE_URL || "";

app.use(cors());
app.use(express.json());

const pool = databaseUrl ? new pg.Pool({ connectionString: databaseUrl }) : null;

async function ensureSchema() {
    if (!pool) {
        return;
    }
    await pool.query(`
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
}

app.get("/healthz", async (_req, res) => {
    if (!pool) {
        return res.status(200).json({ status: "ok", db: "skipped" });
    }

    try {
        await pool.query("SELECT 1");
        return res.status(200).json({ status: "ok", db: "ok" });
    } catch (_error) {
        return res.status(503).json({ status: "degraded", db: "error" });
    }
});

app.get("/api/events", async (req, res) => {
    if (!pool) {
        return res.status(500).json({ error: "DATABASE_URL is not configured" });
    }

    const month = String(req.query.month || "");
    if (!month.match(/^\d{4}-\d{2}$/)) {
        return res.status(400).json({ error: "month must be YYYY-MM" });
    }

    const monthStart = `${month}-01`;
    const sql = `
        SELECT id, title, event_date, start_time, end_time, notes
        FROM calendar_events
        WHERE event_date >= $1::date
          AND event_date < ($1::date + INTERVAL '1 month')
        ORDER BY event_date, start_time NULLS FIRST, id
    `;

    const result = await pool.query(sql, [monthStart]);
    return res.json({ events: result.rows });
});

app.post("/api/events", async (req, res) => {
    if (!pool) {
        return res.status(500).json({ error: "DATABASE_URL is not configured" });
    }

    const title = String(req.body.title || "").trim();
    const eventDate = String(req.body.event_date || "").trim();
    const startTime = String(req.body.start_time || "").trim();
    const endTime = String(req.body.end_time || "").trim();
    const notes = String(req.body.notes || "").trim();

    if (!title) {
        return res.status(400).json({ error: "title is required" });
    }
    if (!eventDate.match(/^\d{4}-\d{2}-\d{2}$/)) {
        return res.status(400).json({ error: "event_date must be YYYY-MM-DD" });
    }

    const normalizedStart = startTime || null;
    const normalizedEnd = endTime || null;
    const normalizedNotes = notes || null;

    const result = await pool.query(
        `
        INSERT INTO calendar_events (title, event_date, start_time, end_time, notes)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, title, event_date, start_time, end_time, notes
        `,
        [title, eventDate, normalizedStart, normalizedEnd, normalizedNotes]
    );

    return res.status(201).json({ event: result.rows[0] });
});

app.delete("/api/events/:id", async (req, res) => {
    if (!pool) {
        return res.status(500).json({ error: "DATABASE_URL is not configured" });
    }

    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) {
        return res.status(400).json({ error: "id must be a positive integer" });
    }

    const result = await pool.query("DELETE FROM calendar_events WHERE id = $1", [id]);
    if (result.rowCount === 0) {
        return res.status(404).json({ error: "event not found" });
    }

    return res.status(204).send();
});

app.get("/api/version", (_req, res) => {
    res.json({ name: "calendar-api", version: "0.1.0" });
});

ensureSchema()
    .then(() => {
        app.listen(port, () => {
            console.log(`api listening on ${port}`);
        });
    })
    .catch((error) => {
        console.error("failed to initialize schema", error);
        process.exit(1);
    });
