from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class Side(StrEnum):
    BUY = "BUY"
    SELL = "SELL"


class Quote(BaseModel):
    symbol: str
    name: str
    instrument_type: str
    lot_size: int
    tick_size: Decimal
    ltp: Decimal
    bid: Decimal
    ask: Decimal
    change: Decimal
    change_percent: Decimal
    timestamp: datetime


class PlaceOrderRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=64)
    side: Side
    quantity: int = Field(gt=0, le=100_000)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, value: str) -> str:
        return value.strip().upper()


class Order(BaseModel):
    id: UUID
    symbol: str
    side: Side
    quantity: int
    average_price: Decimal
    status: str
    created_at: datetime


class Position(BaseModel):
    symbol: str
    quantity: int
    average_price: Decimal
    ltp: Decimal
    realized_pnl: Decimal
    unrealized_pnl: Decimal
    net_pnl: Decimal


class Portfolio(BaseModel):
    initial_balance: Decimal
    cash_balance: Decimal
    market_value: Decimal
    equity: Decimal
    realized_pnl: Decimal
    unrealized_pnl: Decimal
    total_pnl: Decimal
    positions: list[Position]


class TradingSnapshot(BaseModel):
    quotes: list[Quote]
    portfolio: Portfolio
    orders: list[Order]
