import test from 'node:test'; import assert from 'node:assert/strict'; import { tick,priceFor } from './market.js';
test('market ticks keep supported prices positive',()=>{const quotes=tick();assert.ok(quotes.length>=5);for(const q of quotes){assert.ok(q.price>0);assert.equal(priceFor(q.symbol),q.price);}});
