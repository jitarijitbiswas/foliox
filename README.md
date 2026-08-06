# NSE Options Paper Trading Platform

The repository is being migrated incrementally from the original FolioX
TypeScript proof of concept to the production Flutter/FastAPI architecture.
Existing `client/` and `server/` folders are retained temporarily as reference;
new development lives in `frontend/` and `backend/`.

Read the [target architecture](docs/architecture.md) before contributing.

## New stack

- `backend/`: FastAPI, SQLAlchemy async, PostgreSQL, Redis and typed provider ports
- `frontend/`: Flutter, Material 3, Riverpod, Go Router, Dio, WebSocket and Hive
- `docs/`: architectural decisions, invariants and delivery sequence

The app simulates trading only. It does not route orders to a broker or exchange.
Live data requires a licensed provider adapter, intentionally marked as a TODO.

## Google authentication

Foliox uses Google ID tokens only for initial identity verification. The Cloudflare
Worker validates Google's signature, issuer, audience and expiry, then creates a
revocable 30-day Foliox session. All orders, positions, watchlists and trade history
are scoped to the authenticated account.

Create a Web OAuth client in Google Cloud and add
`https://foliox.foliox.workers.dev` as an authorized JavaScript origin. Create an
Android OAuth client for package `com.papertrading.nse_paper_trading` with SHA-1
`E3:3D:E2:CA:29:36:95:8D:61:F3:B0:D5:B4:1C:BB:98:20:B4:CB:79`.

Configure and build with the same Web client ID:

```powershell
npx wrangler secret put GOOGLE_CLIENT_IDS
cd frontend
flutter build web --release --dart-define=GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
flutter build apk --release --dart-define=GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Apply `cloudflare/schema.sql` to D1 before deploying the authenticated Worker.

## Test the buy/sell demo

Start the API:

```powershell
cd backend
python -m pip install -e ".[dev]"
python -m uvicorn app.main:app --reload
```

In a second terminal, start Flutter web:

```powershell
cd frontend
flutter pub get
flutter run -d chrome
```

The dashboard uses a simulated market feed. Select **BUY** or **SELL**, choose the
number of lots, and confirm the market order. Options enforce their configured lot
size. Account metrics and open positions refresh after the fill and every two
seconds. The reset icon restores the ₹10,00,000 demo balance.

Demo REST resources are documented at `http://127.0.0.1:8000/docs` under
`/api/v1/demo`. This in-memory adapter is intentionally non-durable: restarting
FastAPI resets orders and positions. It is an end-to-end test harness, not the
production PostgreSQL execution engine.

## Legacy prototype

Production-oriented paper trading simulator for Indian equities.

## Stack

- React + Vite + Tailwind CSS + Zustand
- Node.js + Express + REST APIs
- PostgreSQL
- Socket.IO WebSockets
- JWT authentication

## Structure

```text
client/                 React application
  src/App.tsx           Login, dashboard, trade, portfolio, orders, history
  src/store.ts          Zustand session and market state
server/
  src/routes/           Thin HTTP controllers
  src/services/         Market, execution, portfolio and P&L logic
  src/middleware/       JWT authorization
db/schema.sql           PostgreSQL schema and indexes
docker-compose.yml      Local PostgreSQL
```

## Setup

1. Copy `.env.example` to `.env`.
2. Start PostgreSQL: `docker compose up -d`.
3. Apply `db/schema.sql` to the `foliox` database.
4. Install dependencies: `npm install`.
5. Start both apps: `npm run dev`.

Frontend: `http://localhost:5173`

API/WebSocket: `http://localhost:4000`

## REST API

- `POST /api/auth/signup`
- `POST /api/auth/login`
- `GET /api/market`
- `GET /api/dashboard`
- `POST /api/orders`
- `PATCH /api/orders/:id/cancel`
- `POST /api/watchlist/:symbol`
- `DELETE /api/watchlist/:symbol`

Authenticated endpoints require `Authorization: Bearer <JWT>`.

## Trading behavior

Market orders fill immediately at the latest simulated quote. Limit BUY orders
fill at or below the limit; limit SELL orders fill at or above it. The execution
engine rejects invalid quantities, insufficient funds, overselling, and unknown
symbols. Every account starts with ₹10,00,000.
