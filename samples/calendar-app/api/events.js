const { ensureSchema, getPool } = require("./_lib/db");
const { json, parseBody } = require("./_lib/http");

module.exports = async function handler(req, res) {
    const dbReady = await ensureSchema();
    if (!dbReady) {
        return json(res, 500, { error: "DATABASE_URL or POSTGRES_URL is required" });
    }

    const db = getPool();

    if (req.method === "GET") {
        const month = String(req.query.month || "");
        if (!month.match(/^\d{4}-\d{2}$/)) {
            return json(res, 400, { error: "month must be YYYY-MM" });
        }

        const monthStart = `${month}-01`;
        const result = await db.query(
            `
            SELECT id, title, event_date, start_time, end_time, notes
            FROM calendar_events
            WHERE event_date >= $1::date
              AND event_date < ($1::date + INTERVAL '1 month')
            ORDER BY event_date, start_time NULLS FIRST, id
            `,
            [monthStart]
        );

        return json(res, 200, { events: result.rows });
    }

    if (req.method === "POST") {
        const body = parseBody(req);
        const title = String(body.title || "").trim();
        const eventDate = String(body.event_date || "").trim();
        const startTime = String(body.start_time || "").trim() || null;
        const endTime = String(body.end_time || "").trim() || null;
        const notes = String(body.notes || "").trim() || null;

        if (!title) {
            return json(res, 400, { error: "title is required" });
        }
        if (!eventDate.match(/^\d{4}-\d{2}-\d{2}$/)) {
            return json(res, 400, { error: "event_date must be YYYY-MM-DD" });
        }

        const result = await db.query(
            `
            INSERT INTO calendar_events (title, event_date, start_time, end_time, notes)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, title, event_date, start_time, end_time, notes
            `,
            [title, eventDate, startTime, endTime, notes]
        );

        return json(res, 201, { event: result.rows[0] });
    }

    res.setHeader("Allow", "GET, POST");
    return json(res, 405, { error: "method not allowed" });
};
