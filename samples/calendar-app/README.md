# Calendar App Sample

公開可能な最小構成のサンプルです。

## Stack
- Frontend: React (Vite)
- Backend: Express (Node.js)
- Database: PostgreSQL 16
- CI: GitHub Actions + ShadowCI template

## Run
```bash
cp .env.example .env
docker compose up --build
```

- Web: http://localhost:5173
- API Health: http://localhost:3001/healthz
- API Events: `GET/POST/DELETE /api/events`

## Release Flow
1. `npm install`
2. `npm run lint && npm run test && npm run build`
3. `git tag -a calendar-sample-v0.1.0 -m "release: calendar sample v0.1.0"`
4. `git push origin main --tags`
