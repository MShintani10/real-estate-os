const { ensureSchema, getPool } = require("./_lib/db");

module.exports = async function handler(_req, res) {
    try {
        const ready = await ensureSchema();
        if (!ready) {
            return res.status(200).json({ status: "ok", db: "missing_config" });
        }

        await getPool().query("SELECT 1");
        return res.status(200).json({ status: "ok", db: "ok" });
    } catch (_error) {
        return res.status(503).json({ status: "degraded", db: "error" });
    }
};
