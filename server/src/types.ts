import type { Request } from 'express';
export type AuthedRequest = Request & { userId?: string };
export type Side = 'BUY'|'SELL';
export type OrderType = 'MARKET'|'LIMIT';
