export type Quote={symbol:string;name:string;price:number;change:number};
export type Account={available_balance:string;used_margin:string;total_pnl:string};
export type Position={id:string;symbol:string;quantity:number;avg_price:string;realized_pnl:string};
export type Order={id:string;symbol:string;side:'BUY'|'SELL';quantity:number;price:string;order_type:'MARKET'|'LIMIT';status:string;created_at:string};
export type Trade={id:string;symbol:string;side:'BUY'|'SELL';quantity:number;price:string;pnl:string;executed_at:string};
export type Dashboard={account:Account;positions:Position[];orders:Order[];trades:Trade[];watchlist:string[];instruments:Quote[]};
