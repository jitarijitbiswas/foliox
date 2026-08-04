export const instruments = [
  {symbol:'RELIANCE',name:'Reliance Industries',price:2987.65,previousClose:2950.45}, {symbol:'TCS',name:'Tata Consultancy Services',price:4218.20,previousClose:4238.55},
  {symbol:'HDFCBANK',name:'HDFC Bank',price:1984.45,previousClose:1970.05}, {symbol:'INFY',name:'Infosys',price:1841.30,previousClose:1828.90},
  {symbol:'ICICIBANK',name:'ICICI Bank',price:1432.75,previousClose:1418.40}, {symbol:'SBIN',name:'State Bank of India',price:812.60,previousClose:805.15},
  {symbol:'ITC',name:'ITC Limited',price:421.80,previousClose:425.10}, {symbol:'MARUTI',name:'Maruti Suzuki',price:12642.00,previousClose:12520.00}
];
const prices=new Map(instruments.map(i=>[i.symbol,i.price]));
export function tick(){ return instruments.map(i=>{ const current=prices.get(i.symbol)!; const next=Number(Math.max(1,current*(1+(Math.random()-.5)*.0015)).toFixed(2)); prices.set(i.symbol,next); return {symbol:i.symbol,name:i.name,price:next,change:Number(((next-i.previousClose)/i.previousClose*100).toFixed(2))}; }); }
export function priceFor(symbol:string){ return prices.get(symbol); }
