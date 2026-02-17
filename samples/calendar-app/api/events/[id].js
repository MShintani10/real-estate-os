const { ensureSchema, getPool } = require("../_lib/db");
const { json } = require("../_lib/http");

module.exports = async function handler(req, res) {
    if (req.method !== "DELETE") {
        res.setHeader("Allow", "DELETE");
        return json(res, 405, { error: "method not allowed" });
    }

    const dbReady = await ensureSchema();
    if (!dbReady) {
        return json(res, 500, { error: "DATABASE_URL or POSTGRES_URL is required" });
    }

    const id = Number(req.query.id);
    if (!Number.isInteger(id) || id <= 0) {
        return json(res, 400, { error: "id must be a positive integer" });
    }

    const result = await getPool().query("DELETE FROM calendar_events WHERE id = $1", [id]);
    if (result.rowCount === 0) {
        return json(res, 404, { error: "event not found" });
    }

    return res.status(204).send();
};
