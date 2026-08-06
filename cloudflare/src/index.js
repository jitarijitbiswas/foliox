const NSE_BASE = 'https://www.nseindia.com';
const INITIAL_BALANCE = 1_000_000;
const LOT_SIZE = 65;
const LIVE_CACHE_MS = 900;
let niftyCache;
const equityCache = new Map();
let googleKeysCache;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);

    const headers = {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    };
    try {
      if (request.method === 'POST' && url.pathname === '/api/v1/auth/google') {
        return json(await googleLogin(request, env), 200, headers);
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/auth/logout') {
        await logout(request, env.DB);
        return json({ ok: true }, 200, headers);
      }
      const account = await requireAccount(request, env.DB);
      if (request.method === 'GET' && url.pathname === '/api/v1/auth/me') {
        return json({ user: account }, 200, headers);
      }
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
        await processPendingOrders(env.DB, account.id, quotes);
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
      if (request.method === 'DELETE' &&
          url.pathname.startsWith('/api/v1/trading/pending-orders/')) {
        const pendingId = url.pathname.slice('/api/v1/trading/pending-orders/'.length);
        await env.DB.prepare(`UPDATE pending_orders SET status='CANCELLED', updated_at=?
          WHERE id=? AND account_id=? AND status='PENDING'`)
          .bind(new Date().toISOString(), pendingId, account.id).run();
        return json({ ok: true }, 200, headers);
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/trading/reset') {
        await env.DB.batch([
          env.DB.prepare('DELETE FROM trade_events WHERE account_id = ?').bind(account.id),
          env.DB.prepare('DELETE FROM orders WHERE account_id = ?').bind(account.id),
          env.DB.prepare('DELETE FROM pending_orders WHERE account_id = ?').bind(account.id),
        ]);
        return json({ ok: true }, 200, headers);
      }
      return json({ detail: 'Route not found' }, 404, headers);
    } catch (error) {
      console.error(error);
      return json({ detail: error.message || 'Request failed' }, error.status || 502, headers);
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(monitorOpenOrders(env.DB));
  },
};

async function monitorOpenOrders(db) {
  const { results } = await db.prepare(
    `SELECT DISTINCT account_id FROM orders WHERE status='OPEN'
     UNION SELECT DISTINCT account_id FROM pending_orders WHERE status='PENDING'`,
  ).all();
  if (!results.length) return;
  const chain = await loadNiftyChain();
  for (const row of results) {
    const quotes = await loadAccountQuotes(db, row.account_id, chain);
    await processPendingOrders(db, row.account_id, quotes);
    await processExits(db, row.account_id, quotes);
  }
}

async function requireAccount(request, db) {
  const authorization = request.headers.get('authorization') || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
  if (!token) throw new HttpError(401, 'Authentication required');
  const tokenHash = await sha256(token);
  const now = new Date().toISOString();
  const account = await db.prepare(`SELECT a.id, a.email, a.name, a.picture
    FROM sessions s JOIN accounts a ON a.id=s.account_id
    WHERE s.token_hash=? AND s.expires_at>?`).bind(tokenHash, now).first();
  if (!account) throw new HttpError(401, 'Session expired. Sign in again.');
  await db.prepare('UPDATE sessions SET last_used_at=? WHERE token_hash=?')
    .bind(now, tokenHash).run();
  return account;
}

async function googleLogin(request, env) {
  const body = await request.json();
  if (!body.id_token) throw new HttpError(400, 'Google ID token is required');
  const claims = await verifyGoogleIdToken(body.id_token, env.GOOGLE_CLIENT_IDS || '');
  if (!claims.email || claims.email_verified !== true) {
    throw new HttpError(401, 'A verified Google email is required');
  }
  const now = new Date().toISOString();
  const id = `google:${claims.sub}`;
  await env.DB.prepare(`INSERT INTO accounts(id, google_sub, email, name, picture, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(google_sub) DO UPDATE SET email=excluded.email, name=excluded.name,
      picture=excluded.picture, updated_at=excluded.updated_at`)
    .bind(id, claims.sub, claims.email, claims.name || claims.email,
      claims.picture || '', now, now).run();
  const sessionToken = randomToken();
  const tokenHash = await sha256(sessionToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM sessions WHERE expires_at<=?').bind(now),
    env.DB.prepare(`INSERT INTO sessions(token_hash, account_id, expires_at, created_at, last_used_at)
      VALUES (?, ?, ?, ?, ?)`).bind(tokenHash, id, expiresAt, now, now),
  ]);
  return {
    token: sessionToken,
    expires_at: expiresAt,
    user: { id, email: claims.email, name: claims.name || claims.email, picture: claims.picture || '' },
  };
}

async function logout(request, db) {
  const authorization = request.headers.get('authorization') || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
  if (token) await db.prepare('DELETE FROM sessions WHERE token_hash=?').bind(await sha256(token)).run();
}

async function verifyGoogleIdToken(token, configuredClientIds) {
  const clientIds = configuredClientIds.split(',').map((value) => value.trim()).filter(Boolean);
  if (!clientIds.length) throw new HttpError(503, 'Google authentication is not configured');
  const parts = token.split('.');
  if (parts.length !== 3) throw new HttpError(401, 'Invalid Google token');
  const header = JSON.parse(decodeBase64Url(parts[0]));
  const claims = JSON.parse(decodeBase64Url(parts[1]));
  if (header.alg !== 'RS256' || !header.kid) throw new HttpError(401, 'Unsupported Google token');
  let keys = await googlePublicKeys();
  let jwk = keys.find((key) => key.kid === header.kid);
  if (!jwk) {
    googleKeysCache = null;
    keys = await googlePublicKeys();
    jwk = keys.find((key) => key.kid === header.kid);
  }
  if (!jwk) throw new HttpError(401, 'Unknown Google signing key');
  return verifyGoogleSignature(parts, claims, jwk, clientIds);
}

async function verifyGoogleSignature(parts, claims, jwk, clientIds) {
  const key = await crypto.subtle.importKey('jwk', jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key,
    base64UrlBytes(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  const now = Math.floor(Date.now() / 1000);
  if (!valid || !['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
      !clientIds.includes(claims.aud) || Number(claims.exp) <= now || Number(claims.iat) > now + 60) {
    throw new HttpError(401, 'Google token verification failed');
  }
  return claims;
}

async function googlePublicKeys() {
  if (googleKeysCache?.expiresAt > Date.now()) return googleKeysCache.keys;
  const response = await fetch('https://www.googleapis.com/oauth2/v3/certs');
  if (!response.ok) throw new HttpError(502, 'Unable to load Google signing keys');
  const payload = await response.json();
  const maxAge = Number(response.headers.get('cache-control')?.match(/max-age=(\d+)/)?.[1] || 3600);
  googleKeysCache = { keys: payload.keys, expiresAt: Date.now() + maxAge * 1000 };
  return googleKeysCache.keys;
}

function decodeBase64Url(value) {
  return new TextDecoder().decode(base64UrlBytes(value));
}

function base64UrlBytes(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '='));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(value, status, headers = {}) {
  return new Response(JSON.stringify(value), { status, headers });
}

async function nseJson(path, referer = `${NSE_BASE}/option-chain?symbol=NIFTY`) {
  const liveUrl = new URL(path, NSE_BASE);
  liveUrl.searchParams.set('_ts', Date.now().toString());
  const common = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140 Safari/537.36',
    accept: 'application/json,text/plain,*/*',
    'accept-language': 'en-US,en;q=0.9',
    referer,
  };
  let response = await fetch(liveUrl, {
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
  liveUrl.searchParams.set('_ts', Date.now().toString());
  response = await fetch(liveUrl, {
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
    FROM orders WHERE account_id=? AND status='OPEN'
    UNION SELECT symbol, CASE WHEN option_type='' THEN 'EQUITY' ELSE 'OPTION' END
    FROM pending_orders WHERE account_id=? AND status='PENDING'`)
    .bind(accountId, accountId, accountId).all();
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
  const orderType = String(body.order_type || 'MARKET').toUpperCase();
  const quantity = Number(body.quantity);
  const quote = chain.quotes.find((item) => item.symbol === body.symbol) ||
    await loadEquityQuote(String(body.symbol || '').toUpperCase());
  if (!quote) throw new Error('Contract is not present in the current NSE option chain');
  if (!['BUY', 'SELL'].includes(side)) throw new Error('Side must be BUY or SELL');
  if (!['MARKET', 'LIMIT', 'STOP_LOSS'].includes(orderType)) {
    throw new Error('Order type must be MARKET, LIMIT, or STOP_LOSS');
  }
  if (!Number.isInteger(quantity) || quantity <= 0 || quantity % quote.lot_size !== 0) {
    throw new Error(`Quantity must be a positive multiple of ${quote.lot_size}`);
  }
  const entry = side === 'BUY' ? quote.ask : quote.bid;
  const orderPrice = orderType === 'MARKET' ? entry : nullableNumber(body.order_price);
  if (orderType !== 'MARKET' && orderPrice == null) {
    throw new Error('Limit or trigger price is required');
  }
  const target = nullableNumber(body.target_price);
  const stop = nullableNumber(body.stop_loss);
  const riskReference = orderPrice ?? entry;
  if (target != null && (side === 'BUY' ? target <= riskReference : target >= riskReference)) {
    throw new Error(`Target must be ${side === 'BUY' ? 'above' : 'below'} entry price`);
  }
  if (stop != null && (side === 'BUY' ? stop >= riskReference : stop <= riskReference)) {
    throw new Error(`Stop-loss must be ${side === 'BUY' ? 'below' : 'above'} entry price`);
  }
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  if (orderType !== 'MARKET') {
    await db.prepare(`INSERT INTO pending_orders
      (id, account_id, symbol, expiry, strike, option_type, side, quantity,
       order_type, order_price, target_price, stop_loss, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?, ?)`)
      .bind(id, accountId, quote.symbol, quote.expiry, quote.strike, quote.option_type,
        side, quantity, orderType, orderPrice, target, stop, now, now).run();
    return { id, status: 'PENDING', order_type: orderType, order_price: orderPrice };
  }
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

async function processPendingOrders(db, accountId, quotes) {
  const { results } = await db.prepare(
    "SELECT * FROM pending_orders WHERE account_id=? AND status='PENDING'",
  ).bind(accountId).all();
  const quoteMap = new Map(quotes.map((quote) => [quote.symbol, quote]));
  for (const pending of results) {
    const quote = quoteMap.get(pending.symbol);
    if (!quote) continue;
    const executable = pending.side === 'BUY' ? quote.ask : quote.bid;
    const shouldFill = pending.order_type === 'LIMIT'
      ? (pending.side === 'BUY' ? executable <= pending.order_price : executable >= pending.order_price)
      : (pending.side === 'BUY' ? executable >= pending.order_price : executable <= pending.order_price);
    if (!shouldFill) continue;
    const orderId = crypto.randomUUID();
    const now = new Date().toISOString();
    await db.batch([
      db.prepare(`INSERT INTO orders
        (id, account_id, symbol, expiry, strike, option_type, side, quantity, entry_price,
         target_price, stop_loss, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'OPEN', ?, ?)`)
        .bind(orderId, accountId, pending.symbol, pending.expiry, pending.strike,
          pending.option_type, pending.side, pending.quantity, executable,
          pending.target_price, pending.stop_loss, now, now),
      db.prepare(`INSERT INTO trade_events
        (id, order_id, account_id, event_type, price, quantity, reason, created_at)
        VALUES (?, ?, ?, 'ENTRY', ?, ?, ?, ?)`)
        .bind(crypto.randomUUID(), orderId, accountId, executable, pending.quantity,
          pending.order_type, now),
      db.prepare(`UPDATE pending_orders SET status='FILLED', filled_order_id=?, updated_at=?
        WHERE id=? AND account_id=? AND status='PENDING'`)
        .bind(orderId, now, pending.id, accountId),
    ]);
  }
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
  const { results: pendingOrders } = await db.prepare(
    "SELECT * FROM pending_orders WHERE account_id=? ORDER BY created_at DESC",
  ).bind(accountId).all();
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
    pending_orders: pendingOrders,
  };
}

function nullableNumber(value) {
  if (value == null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) throw new Error('Target and stop-loss must be positive numbers');
  return parsed;
}
