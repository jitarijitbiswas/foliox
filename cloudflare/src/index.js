const NSE_BASE = 'https://www.nseindia.com';
const INITIAL_BALANCE = 1_000_000;
const LOT_SIZE = 65;
const LIVE_CACHE_MS = 900;
let niftyCache;
const equityCache = new Map();

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
      if (request.method === 'GET' && url.pathname === '/api/v1/market/search') {
        return json(await searchMarket(url.searchParams.get('q') || ''), 200, headers);
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/watchlist') {
        const result = await addWatchlist(env.DB, account.id, await request.json());
        return json(result, 201, headers);
      }
      if (request.method === 'DELETE' && url.pathname.startsWith('/api/v1/watchlist/')) {
        const symbol = decodeURIComponent(url.pathname.slice('/api/v1/watchlist/'.length));
        await env.DB.prepare('DELETE FROM watchlist WHERE account_id=? AND symbol=?')
          .bind(account.id, symbol).run();
        return json({ ok: true }, 200, headers);
      }
      if (request.method === 'GET' && url.pathname === '/api/v1/trading/snapshot') {
        const chain = await loadNiftyChain();
        const quotes = await loadAccountQuotes(env.DB, account.id, chain);
        await processExits(env.DB, account.id, quotes);
        return json(await snapshot(env.DB, account.id, chain, quotes), 200, headers);
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/trading/orders') {
        const body = await request.json();
        const chain = await loadNiftyChain();
        const order = await placeOrder(env.DB, account.id, body, chain);
        return json(order, 201, headers);
      }
      if (request.method === 'POST' && url.pathname.endsWith('/close') &&
          url.pathname.startsWith('/api/v1/trading/orders/')) {
        const orderId = url.pathname
          .slice('/api/v1/trading/orders/'.length, -'/close'.length);
        const result = await closeTrade(env.DB, account.id, orderId);
        return json(result, 200, headers);
      }
      if (request.method === 'PATCH' && url.pathname.startsWith('/api/v1/trading/orders/')) {
        const orderId = url.pathname.slice('/api/v1/trading/orders/'.length);
        const result = await updateRisk(env.DB, account.id, orderId, await request.json());
        return json(result, 200, headers);
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
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(monitorOpenOrders(env.DB));
  },
};

async function monitorOpenOrders(db) {
  const { results } = await db.prepare(
    "SELECT DISTINCT account_id FROM orders WHERE status = 'OPEN'",
  ).all();
  if (!results.length) return;
  const chain = await loadNiftyChain();
  for (const row of results) {
    const quotes = await loadAccountQuotes(db, row.account_id, chain);
    await processExits(db, row.account_id, quotes);
  }
}

function getAccount(request) {
  const match = request.headers.get('cookie')?.match(/(?:^|;\s*)foliox_account=([^;]+)/);
  return { id: match?.[1] || crypto.randomUUID() };
}

function json(value, status, headers = {}) {
  return new Response(JSON.stringify(value), { status, headers });
}

async function nseJson(path, referer = `${NSE_BASE}/option-chain?symbol=NIFTY`) {
  const common = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140 Safari/537.36',
    accept: 'application/json,text/plain,*/*',
    'accept-language': 'en-US,en;q=0.9',
    referer,
  };
  let response = await fetch(`${NSE_BASE}${path}`, {
    headers: common,
    cache: 'no-store',
  });
  let text = await response.text();
  if (response.ok && text.length > 2) return JSON.parse(text);

  const landing = await fetch(referer, {
    headers: common,
    cache: 'no-store',
  });
  const cookie = landing.headers.get('set-cookie')?.split(',').map((item) => item.split(';')[0]).join('; ');
  response = await fetch(`${NSE_BASE}${path}`, {
    headers: { ...common, ...(cookie ? { cookie } : {}) },
    cache: 'no-store',
  });
  text = await response.text();
  if (!response.ok || text.length <= 2) throw new Error('NSE live data is temporarily unavailable');
  return JSON.parse(text);
}

async function searchMarket(rawQuery) {
  const query = rawQuery.trim();
  if (query.length < 2) return [];
  const chain = await loadNiftyChain();
  let equities = [];
  if (/[A-Za-z]/.test(query)) {
    try {
      equities = await nseJson(
        `/api/smart-search/equity?q=${encodeURIComponent(query)}`,
        `${NSE_BASE}/`,
      );
    } catch (error) {
      console.error(error);
    }
  }
  const normalized = query.toUpperCase().replace(/\s+/g, '');
  const equityResults = equities
    .filter((item) => item.series === 'EQ')
    .slice(0, 8)
    .map((item) => ({
      symbol: item.symbol,
      name: item.companyName,
      instrument_type: 'EQUITY',
      lot_size: 1,
      expiry: '',
      strike: 0,
      option_type: '',
      ltp: Number(item.lastPrice || 0),
      bid: Number(item.lastPrice || 0),
      ask: Number(item.lastPrice || 0),
      change_percent: Number(item.pChange || 0),
    }));
  const optionResults = chain.quotes
    .filter((item) =>
      item.symbol.toUpperCase().includes(normalized) ||
      item.name.toUpperCase().replace(/\s+/g, '').includes(normalized),
    )
    .sort((left, right) =>
      Math.abs(left.strike - chain.underlying) - Math.abs(right.strike - chain.underlying),
    )
    .slice(0, 40);
  return [...equityResults, ...optionResults];
}

async function loadEquityQuote(symbol) {
  const cached = equityCache.get(symbol);
  if (cached && cached.expiresAt > Date.now()) return cached.quote;
  const metadata = await nseJson(
    `/api/NextApi/apiClient/GetQuoteApi?functionName=getMetaData&symbol=${encodeURIComponent(symbol)}`,
    `${NSE_BASE}/`,
  );
  const path = `/api/NextApi/apiClient/GetQuoteApi?functionName=getSymbolData&marketType=${encodeURIComponent(metadata.marketType || 'N')}&series=EQ&symbol=${encodeURIComponent(symbol)}`;
  const payload = await nseJson(path, `${NSE_BASE}/get-quote/equity/${encodeURIComponent(symbol)}`);
  const item = payload.equityResponse?.[0];
  if (!item) throw new Error(`NSE quote unavailable for ${symbol}`);
  const book = item.orderBook;
  const meta = item.metaData;
  const ltp = Number(book.lastPrice || item.tradeInfo?.lastPrice || meta.closePrice);
  const quote = {
    symbol: meta.symbol,
    name: meta.companyName,
    instrument_type: 'EQUITY',
    expiry: '',
    strike: 0,
    option_type: '',
    lot_size: 1,
    ltp,
    bid: Number(book.buyPrice1 || ltp),
    ask: Number(book.sellPrice1 || ltp),
    change_percent: Number(meta.pChange || 0),
    open_interest: 0,
    volume: Number(item.tradeInfo?.totalTradedVolume || 0),
    timestamp: item.lastUpdateTime,
  };
  equityCache.set(symbol, { quote, expiresAt: Date.now() + LIVE_CACHE_MS });
  return quote;
}

async function addWatchlist(db, accountId, body) {
  const symbol = String(body.symbol || '').toUpperCase();
  if (!symbol) throw new Error('Symbol is required');
  const chain = await loadNiftyChain();
  const quote = chain.quotes.find((item) => item.symbol === symbol) || await loadEquityQuote(symbol);
  await db.prepare(`INSERT OR REPLACE INTO watchlist
    (account_id, symbol, instrument_type, name, expiry, strike, option_type, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(accountId, quote.symbol, quote.instrument_type, quote.name, quote.expiry,
      quote.strike, quote.option_type, new Date().toISOString()).run();
  return quote;
}

async function loadAccountQuotes(db, accountId, chain) {
  const { results } = await db.prepare(`SELECT symbol, instrument_type FROM watchlist WHERE account_id=?
    UNION SELECT symbol, CASE WHEN option_type='' THEN 'EQUITY' ELSE 'OPTION' END
    FROM orders WHERE account_id=? AND status='OPEN'`).bind(accountId, accountId).all();
  const chainMap = new Map(chain.quotes.map((item) => [item.symbol, item]));
  const quotes = [];
  for (const row of results) {
    const option = chainMap.get(row.symbol);
    if (option) quotes.push(option);
    else if (row.instrument_type === 'EQUITY') {
      try { quotes.push(await loadEquityQuote(row.symbol)); } catch (error) { console.error(error); }
    }
  }
  return quotes;
}

async function loadNiftyChain() {
  if (niftyCache?.expiresAt > Date.now()) return niftyCache.value;
  const info = await nseJson('/api/option-chain-contract-info?symbol=NIFTY');
  const expiry = info.expiryDates.find((value) => parseNseDate(value) >= startOfToday()) || info.expiryDates[0];
  const payload = await nseJson(`/api/option-chain-v3?type=Indices&symbol=NIFTY&expiry=${encodeURIComponent(expiry)}`);
  const records = payload.records;
  if (!records?.data?.length) throw new Error('NSE returned an empty option chain');
  const quotes = [];
  for (const row of records.data) {
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
        timestamp: records.timestamp,
      });
    }
  }
  const chain = {
    source: 'NSE India',
    is_live: true,
    timestamp: records.timestamp,
    underlying: Number(records.underlyingValue),
    expiry,
    quotes,
  };
  niftyCache = { value: chain, expiresAt: Date.now() + LIVE_CACHE_MS };
  return chain;
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
  const quote = chain.quotes.find((item) => item.symbol === body.symbol) ||
    await loadEquityQuote(String(body.symbol || '').toUpperCase());
  if (!quote) throw new Error('Contract is not present in the current NSE option chain');
  if (!['BUY', 'SELL'].includes(side)) throw new Error('Side must be BUY or SELL');
  if (!Number.isInteger(quantity) || quantity <= 0 || quantity % quote.lot_size !== 0) {
    throw new Error(`Quantity must be a positive multiple of ${quote.lot_size}`);
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

async function updateRisk(db, accountId, orderId, body) {
  const order = await db.prepare(
    "SELECT * FROM orders WHERE id=? AND account_id=? AND status='OPEN'",
  ).bind(orderId, accountId).first();
  if (!order) throw new Error('Open trade not found');
  const target = nullableNumber(body.target_price);
  const stop = nullableNumber(body.stop_loss);
  if (target != null && (order.side === 'BUY' ? target <= order.entry_price : target >= order.entry_price)) {
    throw new Error(`Target must be ${order.side === 'BUY' ? 'above' : 'below'} entry price`);
  }
  if (stop != null && (order.side === 'BUY' ? stop >= order.entry_price : stop <= order.entry_price)) {
    throw new Error(`Stop-loss must be ${order.side === 'BUY' ? 'below' : 'above'} entry price`);
  }
  await db.prepare('UPDATE orders SET target_price=?, stop_loss=?, updated_at=? WHERE id=? AND account_id=?')
    .bind(target, stop, new Date().toISOString(), orderId, accountId).run();
  return { ok: true, target_price: target, stop_loss: stop };
}

async function closeTrade(db, accountId, orderId) {
  const order = await db.prepare(
    "SELECT * FROM orders WHERE id=? AND account_id=? AND status='OPEN'",
  ).bind(orderId, accountId).first();
  if (!order) throw new Error('Open trade not found');
  const chain = await loadNiftyChain();
  const option = chain.quotes.find((item) => item.symbol === order.symbol);
  const quote = option || await loadEquityQuote(order.symbol);
  const exitPrice = order.side === 'BUY' ? quote.bid : quote.ask;
  const direction = order.side === 'BUY' ? 1 : -1;
  const pnl = (exitPrice - order.entry_price) * order.quantity * direction;
  const now = new Date().toISOString();
  await db.batch([
    db.prepare(`UPDATE orders SET status='CLOSED', exit_price=?, exit_reason='MANUAL',
      pnl=?, updated_at=? WHERE id=? AND account_id=? AND status='OPEN'`)
      .bind(exitPrice, pnl, now, orderId, accountId),
    db.prepare(`INSERT INTO trade_events
      (id, order_id, account_id, event_type, price, quantity, reason, created_at)
      VALUES (?, ?, ?, 'EXIT', ?, ?, 'MANUAL', ?)`)
      .bind(crypto.randomUUID(), orderId, accountId, exitPrice, order.quantity, now),
  ]);
  return { ok: true, exit_price: exitPrice, pnl, reason: 'MANUAL' };
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

async function snapshot(db, accountId, chain, accountQuotes) {
  const { results: orders } = await db.prepare(
    'SELECT * FROM orders WHERE account_id = ? ORDER BY created_at DESC',
  ).bind(accountId).all();
  const quoteMap = new Map(accountQuotes.map((quote) => [quote.symbol, quote]));
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
      timestamp: quote?.timestamp || chain.timestamp,
    });
  }
  return {
    ...chain,
    quotes: accountQuotes,
    refreshed_at: new Date().toISOString(),
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
