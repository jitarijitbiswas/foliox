from fastapi import APIRouter

from app.modules.system.api import router as system_router
from app.modules.trading.api import router as trading_router

api_router = APIRouter()
api_router.include_router(system_router, tags=["system"])
api_router.include_router(trading_router, tags=["demo trading"])
