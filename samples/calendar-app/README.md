# Calendar App Sample

React + PostgreSQL を Vercel で公開するためのサンプルです。

## Stack
- Frontend: React (Vite, static export)
- API: Vercel Serverless Functions (`/api/*`)
- Database: PostgreSQL (Vercel Postgres / Neon / Supabase など)

## Local Run
```bash
cp .env.example .env
docker compose up --build
```

- Web: http://localhost:5173
- API Health: http://localhost:3001/healthz
- API Events: `GET/POST/DELETE /api/events`

## Vercel Deploy
1. PostgreSQL を用意し、接続文字列を取得
2. Vercel Project の Environment Variables に `DATABASE_URL` を設定
3. `samples/calendar-app` でデプロイ

```bash
cd samples/calendar-app
vercel
vercel --prod
```

## API Routes
- `GET /api/healthz`
- `GET /api/events?month=YYYY-MM`
- `POST /api/events`
- `DELETE /api/events/:id`
