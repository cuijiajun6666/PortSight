from fastapi import APIRouter, Query

from market_rt_data import fetch_market_intraday

router = APIRouter()


@router.get("/market_intraday")
def get_market_intraday(symbol: list[str] | None = Query(default=None)):
    try:
        result = fetch_market_intraday(symbol)
    except Exception as exc:
        return {
            "ok": False,
            "error": str(exc),
        }

    return {
        **result,
    }


@router.get("/market")
def get_market(symbol: list[str] | None = Query(default=None)):
    return get_market_intraday(symbol)
