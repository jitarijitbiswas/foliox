const NSE_BASE = 'https://www.nseindia.com';
const INITIAL_BALANCE = 1_000_000;
const LOT_SIZE = 65;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);

    const account = getAccount(request);
    const headers = {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'set-cookie': `foliox_account=${account.id}; Path=/; Max-Age=31536000; SameSite=Lax; Secure`,
    };
    try {
      if (request.method === 'GET' && url.pathname === '/api/v1/market/nifty') {
        return json(await loadNiftyChain(), 200, headers);
      }
      if (request.method === 'GET' && url.pathname === '/api/v1/trading/snapshot') {
        const chain = await loadNiftyChain();
        await processExits(env.DB, account.id, chain.quotes);
        return json(await snapshot(env.DB, account.id, chain), 200, headers);
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/trading/orders') {
        const body = await request.json();
        const chain = await loadNiftyChain();
        const order = await placeOrder(env.DB, account.id, body, chain);
        return json(order, 201, headers);
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/trading/reset') {
        await env.DB.batch([
          env.DB.prepare('DELETE FROM trade_events WHERE account_id = ?').bind(account.id),
          env.DB.prepare('DELETE FROM orders WHERE account_id = ?').bind(account.id),
        ]);
        return json({ ok: true }, 200, headers);
      }
      return json({ detail: 'Route not found' }, 404, headers);
    } catch (error) {
      console.error(error);
      return json({ detail: error.message || 'Request failed' }, 502, headers);
    }
  },
};

function getAccount(request) {
  const match = request.headers.get('cookie')?.match(/(?:^|;\s*)foliox_account=([^;]+)/);
  return { id: match?.[1] || crypto.randomUUID() };
}

function json(value, status, headers = {}) {
  return new Response(JSON.stringify(value), { status, headers });
}

async function nseJson(path) {
  const common = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140 Safari/537.36',
    accept: 'application/json,text/plain,*/*',
    'accept-language': 'en-US,en;q=0.9',
    referer: `${NSE_BASE}/option-chain?symbol=NIFTY`,
  };
  let response = await fetch(`${NSE_BASE}${path}`, { headers: common });
  let text = await response.text();
  if (response.ok && text.length > 2) return JSON.parse(text);

  const landing = await fetch(`${NSE_BASE}/option-chain?symbol=NIFTY`, { headers: common });
  const cookie = landing.headers.get('set-cookie')?.split(',').map((item) => item.split(';')[0]).join('; ');
  response = await fetch(`${NSE_BASE}${path}`, {
    headers: { ...common, ...(cookie ? { cookie } : {}) },
  });
  text = await response.text();
  if (!response.ok || text.length <= 2) throw new Error('NSE live data is temporarily unavailable');
  return JSON.parse(text);
}

async function loadNiftyChain() {
  const info = await nseJson('/api/option-chain-contract-info?symbol=NIFTY');
  const expiry = info.expiryDates.find((value) => parseNseDate(value) >= startOfToday()) || info.expiryDates[0];
  const payload = await nseJson(`/api/option-chain-v3?type=Indices&symbol=NIFTY&expiry=${encodeURIComponent(expiry)}`);
  const records = payload.records;
  if (!records?.data?.length) throw new Error('NSE returned an empty option chain');
  const quotes = [];
  for (const row of records.data) {
    if (Math.abs(Number(row.strikePrice) - Number(records.underlyingValue)) > 500) continue;
    if (Number(row.strikePrice) % 50 !== 0) continue;
    for (const optionType of ['CE', 'PE']) {
      const item = row[optionType];
      if (!item || !item.lastPrice) continue;
      quotes.push({
        symbol: item.identifier,
        name: `NIFTY ${expiry.toUpperCase()} ${row.strikePrice} ${optionType}`,
        instrument_type: 'OPTION',
        expiry,
        strike: Number(row.strikePrice),
        option_type: optionType,
        lot_size: LOT_SIZE,
        ltp: Number(item.lastPrice),
        bid: Number(item.buyPrice1 || item.lastPrice),
        ask: Number(item.sellPrice1 || item.lastPrice),
        change_percent: Number(item.pChange || item.PChange || 0),
        open_interest: Number(item.openInterest || 0),
        volume: Number(item.totalTradedVolume || 0),
      });
    }
  }
  return {
    source: 'NSE India',
    is_live: true,
    timestamp: records.timestamp,
    underlying: Number(records.underlyingValue),
    expiry,
    quotes,
  };
}

function parseNseDate(value) {
  const [day, month, year] = value.split('-');
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return Date.UTC(Number(year), months.indexOf(month), Number(day));
}

function startOfToday() {
  const now = new Date();
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
}

async function placeOrder(db, accountId, body, chain) {
  const side = String(body.side || '').toUpperCase();
  const quantity = Number(body.quantity);
  const quote = chain.quotes.find((item) => item.symbol === body.symbol);
  if (!quote) throw new Error('Contract is not present in the current NSE option chain');
  if (!['BUY', 'SELL'].includes(side)) throw new Error('Side must be BUY or SELL');
  if (!Number.isInteger(quantity) || quantity <= 0 || quantity % LOT_SIZE !== 0) {
    throw new Error(`Quantity must be a positive multiple of ${LOT_SIZE}`);
  }
  const entry = side === 'BUY' ? quote.ask : quote.bid;
  const target = nullableNumber(body.target_price);
  const stop = nullableNumber(body.stop_loss);
  if (target != null && (side === 'BUY' ? target <= entry : target >= entry)) {
    throw new Error(`Target must be ${side === 'BUY' ? 'above' : 'below'} entry price`);
  }
  if (stop != null && (side === 'BUY' ? stop >= entry : stop <= entry)) {
    throw new Error(`Stop-loss must be ${side === 'BUY' ? 'below' : 'above'} entry price`);
  }
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await db.batch([
    db.prepare(`INSERT INTO orders
      (id, account_id, symbol, expiry, strike, option_type, side, quantity, entry_price,
       target_price, stop_loss, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'OPEN', ?, ?)`)
      .bind(id, accountId, quote.symbol, quote.expiry, quote.strike, quote.option_type,
        side, quantity, entry, target, stop, now, now),
    db.prepare(`INSERT INTO trade_events
      (id, order_id, account_id, event_type, price, quantity, reason, created_at)
      VALUES (?, ?, ?, 'ENTRY', ?, ?, 'MARKET', ?)`)
      .bind(crypto.randomUUID(), id, accountId, entry, quantity, now),
  ]);
  return { id, status: 'OPEN', entry_price: entry };
}

async function processExits(db, accountId, quotes) {
  const { results } = await db.prepare(
    "SELECT * FROM orders WHERE account_id = ? AND status = 'OPEN'",
  ).bind(accountId).all();
  const quoteMap = new Map(quotes.map((quote) => [quote.symbol, quote]));
  for (const order of results) {
    const quote = quoteMap.get(order.symbol);
    if (!quote) continue;
    const mark = quote.ltp;
    const targetHit = order.target_price != null &&
      (order.side === 'BUY' ? mark >= order.target_price : mark <= order.target_price);
    const stopHit = order.stop_loss != null &&
      (order.side === 'BUY' ? mark <= order.stop_loss : mark >= order.stop_loss);
    if (!targetHit && !stopHit) continue;
    const exitPrice = order.side === 'BUY' ? quote.bid : quote.ask;
    const direction = order.side === 'BUY' ? 1 : -1;
    const pnl = (exitPrice - order.entry_price) * order.quantity * direction;
    const reason = targetHit ? 'TARGET' : 'STOP_LOSS';
    const now = new Date().toISOString();
    await db.batch([
      db.prepare(`UPDATE orders SET status='CLOSED', exit_price=?, exit_reason=?, pnl=?, updated_at=?
        WHERE id=? AND account_id=? AND status='OPEN'`)
        .bind(exitPrice, reason, pnl, now, order.id, accountId),
      db.prepare(`INSERT INTO trade_events
        (id, order_id, account_id, event_type, price, quantity, reason, created_at)
        VALUES (?, ?, ?, 'EXIT', ?, ?, ?, ?)`)
        .bind(crypto.randomUUID(), order.id, accountId, exitPrice, order.quantity, reason, now),
    ]);
  }
}

async function snapshot(db, accountId, chain) {
  const { results: orders } = await db.prepare(
    'SELECT * FROM orders WHERE account_id = ? ORDER BY created_at DESC',
  ).bind(accountId).all();
  const quoteMap = new Map(chain.quotes.map((quote) => [quote.symbol, quote]));
  let cash = INITIAL_BALANCE;
  let realized = 0;
  let unrealized = 0;
  const positions = [];
  for (const order of orders) {
    const direction = order.side === 'BUY' ? 1 : -1;
    cash -= order.entry_price * order.quantity * direction;
    if (order.status === 'CLOSED') {
      cash += order.exit_price * order.quantity * direction;
      realized += order.pnl;
      continue;
    }
    const quote = quoteMap.get(order.symbol);
    const ltp = quote?.ltp ?? order.entry_price;
    const pnl = (ltp - order.entry_price) * order.quantity * direction;
    unrealized += pnl;
    positions.push({
      order_id: order.id,
      symbol: order.symbol,
      side: order.side,
      quantity: order.quantity,
      average_price: order.entry_price,
      ltp,
      target_price: order.target_price,
      stop_loss: order.stop_loss,
      realized_pnl: 0,
      unrealized_pnl: pnl,
      net_pnl: pnl,
    });
  }
  return {
    ...chain,
    portfolio: {
      cash_balance: cash,
      equity: INITIAL_BALANCE + realized + unrealized,
      realized_pnl: realized,
      unrealized_pnl: unrealized,
      total_pnl: realized + unrealized,
      positions,
    },
    orders,
  };
}

function nullableNumber(value) {
  if (value == null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) throw new Error('Target and stop-loss must be positive numbers');
  return parsed;
}
