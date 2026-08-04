import asyncio
import random
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal
from uuid import uuid4

from fastapi import HTTPException, status

from app.modules.trading.schemas import (
    Order,
    PlaceOrderRequest,
    Portfolio,
    Position,
    Quote,
    Side,
    TradingSnapshot,
)

MONEY = Decimal("0.01")


def money(value: Decimal) -> Decimal:
    return value.quantize(MONEY, rounding=ROUND_HALF_UP)


@dataclass(slots=True)
class Instrument:
    symbol: str
    name: str
    instrument_type: str
    lot_size: int
    tick_size: Decimal
    previous_close: Decimal
    ltp: Decimal


@dataclass(slots=True)
class PositionState:
    quantity: int
    average_price: Decimal
    realized_pnl: Decimal = Decimal("0")


class DemoTradingService:
    """Single-process demo adapter for testing the end-to-end trading workflow.

    TODO(trading): replace this adapter with PostgreSQL repositories, Redis quote
    cache, durable commands, and the production execution worker.
    """

    initial_balance = Decimal("1000000.00")

    def __init__(self, seed: int = 7) -> None:
        self._lock = asyncio.Lock()
        self._random = random.Random(seed)
        self._instruments = self._create_instruments()
        self._positions: dict[str, PositionState] = {}
        self._orders: list[Order] = []
        self._cash = self.initial_balance

    @staticmethod
    def _create_instruments() -> dict[str, Instrument]:
        rows = [
            ("NIFTY", "Nifty 50", "INDEX", 1, "0.05", "24700.00"),
            ("BANKNIFTY", "Nifty Bank", "INDEX", 1, "0.05", "53500.00"),
            ("NIFTY24AUG24700CE", "NIFTY 24 AUG 24700 CE", "OPTION", 75, "0.05", "215.00"),
            ("NIFTY24AUG24700PE", "NIFTY 24 AUG 24700 PE", "OPTION", 75, "0.05", "198.00"),
            ("BANKNIFTY24AUG53500CE", "BANKNIFTY 24 AUG 53500 CE", "OPTION", 30, "0.05", "440.00"),
            ("BANKNIFTY24AUG53500PE", "BANKNIFTY 24 AUG 53500 PE", "OPTION", 30, "0.05", "425.00"),
            ("RELIANCE", "Reliance Industries", "EQUITY", 1, "0.05", "2987.65"),
            ("TCS", "Tata Consultancy Services", "EQUITY", 1, "0.05", "4218.20"),
        ]
        return {
            symbol: Instrument(
                symbol, name, kind, lot, Decimal(tick), Decimal(price), Decimal(price)
            )
            for symbol, name, kind, lot, tick, price in rows
        }

    def _move_prices(self) -> None:
        for instrument in self._instruments.values():
            movement = Decimal(str(self._random.uniform(-0.0008, 0.0008)))
            instrument.ltp = money(
                max(instrument.tick_size, instrument.ltp * (Decimal("1") + movement))
            )

    @staticmethod
    def _quote(instrument: Instrument) -> Quote:
        spread = max(instrument.tick_size, money(instrument.ltp * Decimal("0.0002")))
        change = money(instrument.ltp - instrument.previous_close)
        change_percent = money(change / instrument.previous_close * Decimal("100"))
        return Quote(
            symbol=instrument.symbol,
            name=instrument.name,
            instrument_type=instrument.instrument_type,
            lot_size=instrument.lot_size,
            tick_size=instrument.tick_size,
            ltp=instrument.ltp,
            bid=money(instrument.ltp - spread),
            ask=money(instrument.ltp + spread),
            change=change,
            change_percent=change_percent,
            timestamp=datetime.now(UTC),
        )

    async def quotes(self, query: str | None = None) -> list[Quote]:
        async with self._lock:
            self._move_prices()
            normalized = (query or "").strip().upper()
            return [
                self._quote(item)
                for item in self._instruments.values()
                if not normalized or normalized in item.symbol or normalized in item.name.upper()
            ]

    async def place_order(self, command: PlaceOrderRequest) -> Order:
        async with self._lock:
            instrument = self._instruments.get(command.symbol)
            if instrument is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown instrument")
            if instrument.instrument_type == "INDEX":
                raise HTTPException(
                    status.HTTP_422_UNPROCESSABLE_CONTENT, "Indices cannot be traded"
                )
            if command.quantity % instrument.lot_size != 0:
                raise HTTPException(
                    status.HTTP_422_UNPROCESSABLE_CONTENT,
                    f"Quantity must be a multiple of lot size {instrument.lot_size}",
                )

            quote = self._quote(instrument)
            fill_price = quote.ask if command.side is Side.BUY else quote.bid
            fill_value = money(fill_price * command.quantity)
            if command.side is Side.BUY and fill_value > self._cash:
                raise HTTPException(
                    status.HTTP_422_UNPROCESSABLE_CONTENT, "Insufficient virtual balance"
                )

            self._apply_fill(command.symbol, command.side, command.quantity, fill_price)
            self._cash = money(
                self._cash - fill_value if command.side is Side.BUY else self._cash + fill_value
            )
            order = Order(
                id=uuid4(),
                symbol=command.symbol,
                side=command.side,
                quantity=command.quantity,
                average_price=fill_price,
                status="FILLED",
                created_at=datetime.now(UTC),
            )
            self._orders.insert(0, order)
            return order

    def _apply_fill(self, symbol: str, side: Side, quantity: int, price: Decimal) -> None:
        signed_fill = quantity if side is Side.BUY else -quantity
        current = self._positions.get(symbol)
        if current is None:
            self._positions[symbol] = PositionState(signed_fill, price)
            return

        old_quantity = current.quantity
        same_direction = (old_quantity > 0 and signed_fill > 0) or (
            old_quantity < 0 and signed_fill < 0
        )
        if same_direction:
            total = abs(old_quantity) + quantity
            current.average_price = money(
                (current.average_price * abs(old_quantity) + price * quantity) / total
            )
            current.quantity += signed_fill
            return

        closing_quantity = min(abs(old_quantity), quantity)
        direction = Decimal("1") if old_quantity > 0 else Decimal("-1")
        current.realized_pnl = money(
            current.realized_pnl + (price - current.average_price) * closing_quantity * direction
        )
        new_quantity = old_quantity + signed_fill
        if new_quantity == 0:
            current.quantity = 0
        elif (new_quantity > 0) != (old_quantity > 0):
            current.quantity = new_quantity
            current.average_price = price
        else:
            current.quantity = new_quantity

    def _portfolio_unlocked(self) -> Portfolio:
        positions: list[Position] = []
        market_value = Decimal("0")
        total_realized = Decimal("0")
        total_unrealized = Decimal("0")
        for symbol, state in self._positions.items():
            instrument = self._instruments[symbol]
            market_value += instrument.ltp * state.quantity
            unrealized = money((instrument.ltp - state.average_price) * state.quantity)
            total_realized += state.realized_pnl
            total_unrealized += unrealized
            if state.quantity != 0:
                positions.append(
                    Position(
                        symbol=symbol,
                        quantity=state.quantity,
                        average_price=state.average_price,
                        ltp=instrument.ltp,
                        realized_pnl=state.realized_pnl,
                        unrealized_pnl=unrealized,
                        net_pnl=money(state.realized_pnl + unrealized),
                    )
                )
        equity = money(self._cash + market_value)
        return Portfolio(
            initial_balance=self.initial_balance,
            cash_balance=self._cash,
            market_value=money(market_value),
            equity=equity,
            realized_pnl=money(total_realized),
            unrealized_pnl=money(total_unrealized),
            total_pnl=money(equity - self.initial_balance),
            positions=positions,
        )

    async def portfolio(self) -> Portfolio:
        async with self._lock:
            return self._portfolio_unlocked()

    async def orders(self) -> list[Order]:
        async with self._lock:
            return list(self._orders)

    async def snapshot(self) -> TradingSnapshot:
        async with self._lock:
            self._move_prices()
            return TradingSnapshot(
                quotes=[self._quote(item) for item in self._instruments.values()],
                portfolio=self._portfolio_unlocked(),
                orders=list(self._orders),
            )

    async def reset(self) -> TradingSnapshot:
        async with self._lock:
            self._positions.clear()
            self._orders.clear()
            self._cash = self.initial_balance
            return TradingSnapshot(
                quotes=[self._quote(item) for item in self._instruments.values()],
                portfolio=self._portfolio_unlocked(),
                orders=[],
            )


demo_trading_service = DemoTradingService()
