from collections.abc import AsyncIterator, Collection
from typing import Protocol

from app.modules.market_data.domain import MarketTick


class MarketDataProvider(Protocol):
    """Implemented by a licensed vendor adapter; never by the trading engine."""

    async def connect(self) -> None: ...

    async def subscribe(self, instrument_tokens: Collection[str]) -> None: ...

    def ticks(self) -> AsyncIterator[MarketTick]: ...

    async def close(self) -> None: ...


# TODO(market-data): add the selected provider adapter in infrastructure/providers.
