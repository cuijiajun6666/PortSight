from fastapi import APIRouter

from advisor_engine import (
    build_advisor_report,
    get_symbol_advice,
    load_advisor_state,
    load_latest_report,
    sync_advisor_klines,
)


router = APIRouter()


@router.get("/advisor/state")
def get_advisor_state():
    return {
        "ok": True,
        "state": load_advisor_state()
    }


@router.post("/advisor/sync_klines")
def post_sync_advisor_klines(force: bool = False):
    return sync_advisor_klines(force=force)


@router.post("/advisor/refresh")
def post_refresh_advisor(force_sync: bool = False):
    return build_advisor_report(force_sync=force_sync)


@router.get("/advisor/suggestions")
def get_advisor_suggestions(refresh: bool = False):
    if refresh:
        return build_advisor_report(force_sync=False)
    report = load_latest_report()
    if not report.get("ok"):
        return build_advisor_report(force_sync=False)
    return report


@router.get("/advisor/symbol")
def get_advisor_symbol(symbol: str, refresh: bool = False):
    return get_symbol_advice(symbol, refresh=refresh)
