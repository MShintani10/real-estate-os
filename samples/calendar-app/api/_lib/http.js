function json(res, status, body) {
    res.status(status).json(body);
}

function parseBody(req) {
    if (!req.body) {
        return {};
    }

    if (typeof req.body === "string") {
        try {
            return JSON.parse(req.body);
        } catch (_error) {
            return {};
        }
    }

    return req.body;
}

module.exports = {
    json,
    parseBody
};
