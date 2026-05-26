from fastapi import APIRouter

from advisor_engine import (
    add_watch_symbol,
    acknowledge_watch_alert,
    build_advisor_report,
    build_candidate_advice,
    get_advisor_summary,
    get_positions_indicator_debug,
    get_symbol_advice,
    get_watch_alerts,
    load_advisor_state,
    load_latest_report,
    load_watchlist,
    monitor_advisor_price_alerts,
    refresh_watchlist,
    sync_advisor_klines,
    sync_advisor_profiles,
    update_watch_symbol,
)
from advisor_training import (
    get_advisor_model,
    get_training_samples,
    record_training_samples,
    train_advisor_model,
    update_training_targets,
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


@router.post("/advisor/sync_profiles")
def post_sync_advisor_profiles(force: bool = False):
    return sync_advisor_profiles(force=force)


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


@router.get("/advisor/summary")
def get_summary(refresh: bool = False):
    return get_advisor_summary(refresh=refresh)


@router.get("/advisor/debug/indicators")
def get_advisor_indicator_debug(force_sync: bool = False):
    return get_positions_indicator_debug(force_sync=force_sync)


@router.get("/advisor/symbol")
def get_advisor_symbol(symbol: str, refresh: bool = False):
    return get_symbol_advice(symbol, refresh=refresh)


@router.get("/advisor/candidate")
def get_advisor_candidate(symbol: str, refresh: bool = False):
    return build_candidate_advice(symbol, force_sync=refresh)


@router.get("/advisor/watchlist")
def get_advisor_watchlist(refresh: bool = False):
    if refresh:
        return refresh_watchlist(force_sync=False)
    return {
        "ok": True,
        "watchlist": load_watchlist(),
    }


@router.post("/advisor/watchlist")
def post_advisor_watchlist(symbol: str, note: str = "", refresh: bool = True):
    return add_watch_symbol(symbol, note=note, force_sync=refresh)


@router.post("/advisor/watchlist/refresh")
def post_advisor_watchlist_refresh(force_sync: bool = False):
    return refresh_watchlist(force_sync=force_sync)


@router.get("/advisor/alerts")
def get_advisor_alerts(include_acknowledged: bool = False):
    return get_watch_alerts(include_acknowledged=include_acknowledged)


@router.post("/advisor/alerts/ack")
def post_advisor_alert_ack(symbol: str | None = None, alert_id: str | None = None):
    return acknowledge_watch_alert(symbol=symbol, alert_id=alert_id)


@router.post("/advisor/alerts/monitor")
def post_advisor_alert_monitor():
    return monitor_advisor_price_alerts()


@router.patch("/advisor/watchlist")
def patch_advisor_watchlist(symbol: str, status: str | None = None, note: str | None = None, delete: bool = False):
    return update_watch_symbol(symbol, status=status, note=note, delete=delete)


@router.post("/advisor/training_samples/record")
def post_record_training_samples():
    return record_training_samples()


@router.post("/advisor/training_samples/update_targets")
def post_update_training_targets():
    return update_training_targets()


@router.get("/advisor/training_samples")
def get_advisor_training_samples(limit: int = 200, symbol: str | None = None):
    return get_training_samples(limit=limit, symbol=symbol)


@router.post("/advisor/model/train")
def post_train_advisor_model(horizon: int = 20, min_samples: int = 8):
    return train_advisor_model(horizon=horizon, min_samples=min_samples)


@router.get("/advisor/model")
def get_model():
    return get_advisor_model()
