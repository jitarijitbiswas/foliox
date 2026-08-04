from decimal import Decimal

import pytest
from fastapi import HTTPException

from app.modules.trading.schemas import PlaceOrderRequest, Side
from app.modules.trading.service import DemoTradingService


@pytest.mark.asyncio
async def test_buy_then_partial_sell_updates_position_and_cash() -> None:
    service = DemoTradingService(seed=1)

    buy = await service.place_order(
        PlaceOrderRequest(symbol="NIFTY11AUG2625000CE", side=Side.BUY, quantity=130)
    )
    after_buy = await service.portfolio()
    sell = await service.place_order(
        PlaceOrderRequest(symbol="NIFTY11AUG2625000CE", side=Side.SELL, quantity=65)
    )
    after_sell = await service.portfolio()

    assert buy.status == "FILLED"
    assert sell.status == "FILLED"
    assert after_buy.positions[0].quantity == 130
    assert after_sell.positions[0].quantity == 65
    assert after_buy.cash_balance < DemoTradingService.initial_balance
    assert after_sell.cash_balance > after_buy.cash_balance


@pytest.mark.asyncio
async def test_position_reversal_is_supported() -> None:
    service = DemoTradingService()
    await service.place_order(
        PlaceOrderRequest(symbol="BANKNIFTY24AUG53500PE", side=Side.BUY, quantity=30)
    )
    await service.place_order(
        PlaceOrderRequest(symbol="BANKNIFTY24AUG53500PE", side=Side.SELL, quantity=60)
    )

    portfolio = await service.portfolio()

    assert portfolio.positions[0].quantity == -30
    assert portfolio.positions[0].realized_pnl <= Decimal("0")


@pytest.mark.asyncio
async def test_rejects_invalid_lot_quantity() -> None:
    service = DemoTradingService()

    with pytest.raises(HTTPException) as error:
        await service.place_order(
            PlaceOrderRequest(symbol="NIFTY11AUG2625000CE", side=Side.BUY, quantity=1)
        )

    assert error.value.status_code == 422
