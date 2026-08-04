CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  symbol TEXT NOT NULL,
  expiry TEXT NOT NULL,
  strike REAL NOT NULL,
  option_type TEXT NOT NULL,
  side TEXT NOT NULL CHECK (side IN ('BUY', 'SELL')),
  quantity INTEGER NOT NULL,
  entry_price REAL NOT NULL,
  target_price REAL,
  stop_loss REAL,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED')),
  exit_price REAL,
  exit_reason TEXT,
  pnl REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_account_status
  ON orders(account_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS trade_events (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('ENTRY', 'EXIT')),
  price REAL NOT NULL,
  quantity INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(order_id) REFERENCES orders(id)
);

CREATE INDEX IF NOT EXISTS idx_trade_events_account
  ON trade_events(account_id, created_at DESC);

CREATE TABLE IF NOT EXISTS watchlist (
  account_id TEXT NOT NULL,
  symbol TEXT NOT NULL,
  instrument_type TEXT NOT NULL,
  name TEXT NOT NULL,
  expiry TEXT NOT NULL DEFAULT '',
  strike REAL NOT NULL DEFAULT 0,
  option_type TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  PRIMARY KEY(account_id, symbol)
);

CREATE INDEX IF NOT EXISTS idx_watchlist_account
  ON watchlist(account_id, created_at);

CREATE TABLE IF NOT EXISTS pending_orders (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  symbol TEXT NOT NULL,
  expiry TEXT NOT NULL DEFAULT '',
  strike REAL NOT NULL DEFAULT 0,
  option_type TEXT NOT NULL DEFAULT '',
  side TEXT NOT NULL CHECK (side IN ('BUY', 'SELL')),
  quantity INTEGER NOT NULL,
  order_type TEXT NOT NULL CHECK (order_type IN ('LIMIT', 'STOP_LOSS')),
  order_price REAL NOT NULL,
  target_price REAL,
  stop_loss REAL,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'FILLED', 'CANCELLED')),
  filled_order_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pending_orders_account_status
  ON pending_orders(account_id, status, created_at DESC);
