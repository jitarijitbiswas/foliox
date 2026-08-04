from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal


@dataclass(frozen=True, slots=True)
class MarketTick:
    """Vendor-neutral normalized tick. Monetary values are exact decimals."""

    instrument_token: str
    exchange_timestamp: datetime
    received_timestamp: datetime
    last_price: Decimal
    bid_price: Decimal | None = None
    ask_price: Decimal | None = None
    volume: int | None = None
    open_interest: int | None = None
