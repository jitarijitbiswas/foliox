import type pg from 'pg';
import { tx } from '../db.js';
import { priceFor } from './market.js';
import type { OrderType, Side } from '../types.js';
export async function executeOrder(client:pg.PoolClient, order:{id:string,user_id:string,symbol:string,side:Side,quantity:number,price:number}){
  const fill=priceFor(order.symbol) ?? Number(order.price); const signed=order.side==='BUY'?order.quantity:-order.quantity;
  const existing=(await client.query('SELECT * FROM positions WHERE user_id=$1 AND symbol=$2 FOR UPDATE',[order.user_id,order.symbol])).rows[0];
  const account=(await client.query('SELECT * FROM accounts WHERE user_id=$1 FOR UPDATE',[order.user_id])).rows[0];
  if(!account) throw new Error('Account missing');
  if(order.side==='BUY' && Number(account.available_balance)<fill*order.quantity) throw new Error('Insufficient balance');
  let realized=0;
  if(!existing){ if(signed<0) throw new Error('Cannot sell without a position'); await client.query('INSERT INTO positions(user_id,symbol,quantity,avg_price) VALUES($1,$2,$3,$4)',[order.user_id,order.symbol,signed,fill]); }
  else { const oldQty=Number(existing.quantity), nextQty=oldQty+signed; if(nextQty<0) throw new Error('Sell quantity exceeds position'); if(order.side==='BUY'){ const avg=(oldQty*Number(existing.avg_price)+order.quantity*fill)/nextQty; await client.query('UPDATE positions SET quantity=$1,avg_price=$2,updated_at=now() WHERE id=$3',[nextQty,avg,existing.id]); } else { realized=(fill-Number(existing.avg_price))*order.quantity; if(nextQty===0) await client.query('DELETE FROM positions WHERE id=$1',[existing.id]); else await client.query('UPDATE positions SET quantity=$1,realized_pnl=realized_pnl+$2,updated_at=now() WHERE id=$3',[nextQty,realized,existing.id]); } }
  const cashDelta=order.side==='BUY'?-fill*order.quantity:fill*order.quantity;
  await client.query('UPDATE accounts SET available_balance=available_balance+$1,total_pnl=total_pnl+$2,updated_at=now() WHERE user_id=$3',[cashDelta,realized,order.user_id]);
  await client.query("UPDATE orders SET status='EXECUTED',price=$1,executed_at=now() WHERE id=$2",[fill,order.id]);
  await client.query('INSERT INTO trades(order_id,user_id,symbol,side,quantity,price,pnl) VALUES($1,$2,$3,$4,$5,$6,$7)',[order.id,order.user_id,order.symbol,order.side,order.quantity,fill,realized]);
}
export async function placeOrder(userId:string,input:{symbol:string;side:Side;quantity:number;orderType:OrderType;limitPrice?:number}){ const market=priceFor(input.symbol); if(!market) throw new Error('Unknown symbol'); return tx(async client=>{ const pending=input.orderType==='LIMIT'; const result=await client.query('INSERT INTO orders(user_id,symbol,side,quantity,price,order_type,status) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *',[userId,input.symbol,input.side,input.quantity,pending?input.limitPrice:market,input.orderType,pending?'PENDING':'EXECUTED']); const order=result.rows[0]; if(!pending){ order.status='PENDING'; await executeOrder(client,order); } return order; }); }
export async function processLimits(){ const { db }=await import('../db.js'); const pending=(await db.query("SELECT * FROM orders WHERE status='PENDING' ORDER BY created_at LIMIT 100")).rows; for(const order of pending){ const mark=priceFor(order.symbol); const hit=mark&&(order.side==='BUY'?mark<=Number(order.price):mark>=Number(order.price)); if(hit){ try { await tx(client=>executeOrder(client,order)); } catch { /* retry on next tick */ } } } }
