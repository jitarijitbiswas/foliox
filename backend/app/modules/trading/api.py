from fastapi import APIRouter, Query, status

from app.modules.trading.schemas import Order, PlaceOrderRequest, Portfolio, Quote, TradingSnapshot
from app.modules.trading.service import demo_trading_service

router = APIRouter(prefix="/demo")


@router.get("/quotes", response_model=list[Quote])
async def get_quotes(q: str | None = Query(default=None, max_length=64)) -> list[Quote]:
    return await demo_trading_service.quotes(q)


@router.get("/portfolio", response_model=Portfolio)
async def get_portfolio() -> Portfolio:
    return await demo_trading_service.portfolio()


@router.get("/orders", response_model=list[Order])
async def get_orders() -> list[Order]:
    return await demo_trading_service.orders()


@router.get("/snapshot", response_model=TradingSnapshot)
async def get_snapshot() -> TradingSnapshot:
    return await demo_trading_service.snapshot()


@router.post("/orders", response_model=Order, status_code=status.HTTP_201_CREATED)
async def place_order(command: PlaceOrderRequest) -> Order:
    return await demo_trading_service.place_order(command)


@router.post("/reset", response_model=TradingSnapshot)
async def reset_account() -> TradingSnapshot:
    return await demo_trading_service.reset()
