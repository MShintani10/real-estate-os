import { useEffect, useMemo, useState } from "react";

function toMonthString(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    return `${y}-${m}`;
}

function buildCalendarCells(monthString) {
    const [year, month] = monthString.split("-").map(Number);
    const firstDay = new Date(year, month - 1, 1);
    const startWeekday = firstDay.getDay();
    const daysInMonth = new Date(year, month, 0).getDate();

    const cells = [];
    for (let i = 0; i < startWeekday; i += 1) {
        cells.push(null);
    }
    for (let day = 1; day <= daysInMonth; day += 1) {
        cells.push(`${monthString}-${String(day).padStart(2, "0")}`);
    }
    while (cells.length % 7 !== 0) {
        cells.push(null);
    }
    return cells;
}

export function App() {
    const [month, setMonth] = useState(toMonthString(new Date()));
    const [events, setEvents] = useState([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");

    const [title, setTitle] = useState("");
    const [eventDate, setEventDate] = useState("");
    const [startTime, setStartTime] = useState("");
    const [endTime, setEndTime] = useState("");
    const [notes, setNotes] = useState("");

    const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:3001";

    const eventsByDate = useMemo(() => {
        const map = {};
        for (const event of events) {
            const key = String(event.event_date).slice(0, 10);
            if (!map[key]) {
                map[key] = [];
            }
            map[key].push(event);
        }
        return map;
    }, [events]);

    const cells = useMemo(() => buildCalendarCells(month), [month]);

    async function loadEvents() {
        setLoading(true);
        setError("");
        try {
            const response = await fetch(`${apiBaseUrl}/api/events?month=${month}`);
            if (!response.ok) {
                throw new Error(`failed to load events (${response.status})`);
            }
            const json = await response.json();
            setEvents(json.events || []);
        } catch (e) {
            setError(String(e.message || e));
        } finally {
            setLoading(false);
        }
    }

    useEffect(() => {
        loadEvents();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [month]);

    async function createEvent(e) {
        e.preventDefault();
        setError("");

        const payload = {
            title,
            event_date: eventDate,
            start_time: startTime,
            end_time: endTime,
            notes
        };

        const response = await fetch(`${apiBaseUrl}/api/events`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
        });

        if (!response.ok) {
            const json = await response.json().catch(() => ({}));
            setError(json.error || `failed to create event (${response.status})`);
            return;
        }

        setTitle("");
        setEventDate("");
        setStartTime("");
        setEndTime("");
        setNotes("");
        loadEvents();
    }

    async function deleteEvent(id) {
        setError("");
        const response = await fetch(`${apiBaseUrl}/api/events/${id}`, { method: "DELETE" });
        if (!response.ok) {
            setError(`failed to delete event (${response.status})`);
            return;
        }
        loadEvents();
    }

    function shiftMonth(delta) {
        const [year, currentMonth] = month.split("-").map(Number);
        const next = new Date(year, currentMonth - 1 + delta, 1);
        setMonth(toMonthString(next));
    }

    return (
        <main style={{ fontFamily: "sans-serif", maxWidth: 980, margin: "24px auto", padding: "0 16px" }}>
            <h1>Calendar App Sample</h1>
            <p>React + Express + PostgreSQL</p>

            <section style={{ marginBottom: 24 }}>
                <button onClick={() => shiftMonth(-1)}>Prev</button>
                <strong style={{ margin: "0 12px" }}>{month}</strong>
                <button onClick={() => shiftMonth(1)}>Next</button>
                <button onClick={loadEvents} style={{ marginLeft: 12 }}>Reload</button>
            </section>

            {loading && <p>Loading...</p>}
            {error && <p style={{ color: "crimson" }}>{error}</p>}

            <section
                style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(7, 1fr)",
                    gap: 8,
                    marginBottom: 24
                }}
            >
                {cells.map((date, idx) => (
                    <div
                        key={`${date || "empty"}-${idx}`}
                        style={{
                            minHeight: 110,
                            border: "1px solid #d6d6d6",
                            borderRadius: 8,
                            padding: 8,
                            background: date ? "#fff" : "#f3f3f3"
                        }}
                    >
                        {date && (
                            <>
                                <div style={{ fontSize: 12, marginBottom: 8 }}>{date.slice(-2)}</div>
                                <ul style={{ listStyle: "none", padding: 0, margin: 0, fontSize: 12 }}>
                                    {(eventsByDate[date] || []).slice(0, 3).map((event) => (
                                        <li key={event.id} style={{ marginBottom: 4 }}>
                                            <button
                                                onClick={() => deleteEvent(event.id)}
                                                style={{ marginRight: 6 }}
                                                title="Delete"
                                            >
                                                x
                                            </button>
                                            {event.start_time ? `${String(event.start_time).slice(0, 5)} ` : ""}
                                            {event.title}
                                        </li>
                                    ))}
                                </ul>
                            </>
                        )}
                    </div>
                ))}
            </section>

            <section>
                <h2>Create Event</h2>
                <form onSubmit={createEvent} style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                    <input
                        value={title}
                        onChange={(e) => setTitle(e.target.value)}
                        placeholder="title"
                        required
                    />
                    <input
                        value={eventDate}
                        onChange={(e) => setEventDate(e.target.value)}
                        placeholder="YYYY-MM-DD"
                        required
                    />
                    <input
                        value={startTime}
                        onChange={(e) => setStartTime(e.target.value)}
                        placeholder="HH:MM"
                    />
                    <input
                        value={endTime}
                        onChange={(e) => setEndTime(e.target.value)}
                        placeholder="HH:MM"
                    />
                    <input
                        value={notes}
                        onChange={(e) => setNotes(e.target.value)}
                        placeholder="notes"
                        style={{ gridColumn: "1 / span 2" }}
                    />
                    <button type="submit" style={{ width: 180 }}>Add Event</button>
                </form>
            </section>
        </main>
    );
}
