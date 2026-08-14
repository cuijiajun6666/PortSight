import threading
import time as time_module

from fastapi import APIRouter, Query as FastAPIQuery
from moomoo import *

from config import HOST, PORT
from deal_cache import (
    load_deal_cache,
    sync_known_history_deals,
)

router = APIRouter()

OPEN_ORDERS_CACHE_TTL_SECONDS = 20
OPEN_ORDER_HISTORY_START = "2026-04-24"
OPEN_ORDER_HISTORY_END = "2026-04-24"
OPEN_ORDER_HISTORY_CODE = "US.SIDU"

OPEN_ORDER_STATUSES = {
    "SUBMITTING",
    "SUBMITTED",
    "FILLED_PART",
    "WAITING_SUBMIT",
    "PENDING_CANCEL",
    "PENDING_REPLACE",
}

CLOSED_ORDER_STATUSES = {
    "FILLED_ALL",
    "CANCELLED_ALL",
    "CANCELLED_PART",
    "FAILED",
    "DISABLED",
    "DELETED",
}

_open_orders_lock = threading.RLock()
_open_orders_cache = {
    "updated_at": None,
    "source": None,
    "orders": [],
}
_open_orders_cache_time = 0.0


def create_trade_context():
    return OpenSecTradeContext(
        filter_trdmarket=TrdMarket.US,
        host=HOST,
        port=PORT,
        security_firm=SecurityFirm.FUTUAU
    )


def json_value(value):
    try:
        if value != value:
            return None
    except Exception:
        pass
    return value


def frame_to_orders(data):
    orders = []
    for _, row in data.iterrows():
        record = {key: json_value(value) for key, value in row.to_dict().items()}
        record["order_id"] = str(record.get("order_id", ""))
        orders.append(record)
    return orders


def frame_to_deals(data):
    deals = []
    for _, row in data.iterrows():
        record = {key: json_value(value) for key, value in row.to_dict().items()}
        record["deal_id"] = str(record.get("deal_id", ""))
        record["order_id"] = str(record.get("order_id", ""))
        deals.append(record)
    return deals


def order_status_name(order):
    status = order.get("order_status", "")
    return str(status).strip().upper()


def is_open_order(order):
    status = order_status_name(order)
    if status in OPEN_ORDER_STATUSES:
        return True
    if status in CLOSED_ORDER_STATUSES:
        return False
    return bool(status) and status not in CLOSED_ORDER_STATUSES


def query_current_open_orders(code=""):
    trd_ctx = create_trade_context()
    try:
        ret, data = trd_ctx.order_list_query(
            code=code,
            trd_env=TrdEnv.REAL,
            refresh_cache=True,
            order_market=TrdMarket.NONE
        )
    finally:
        trd_ctx.close()

    if ret != RET_OK:
        return {
            "ok": False,
            "error": str(data),
            "source": "order_list_query",
            "orders": []
        }

    return {
        "ok": True,
        "source": "order_list_query",
        "orders": [
            order for order in frame_to_orders(data)
            if is_open_order(order)
        ]
    }


def query_known_sidu_open_order():
    trd_ctx = create_trade_context()
    try:
        ret, data = trd_ctx.history_order_list_query(
            code=OPEN_ORDER_HISTORY_CODE,
            start=OPEN_ORDER_HISTORY_START,
            end=OPEN_ORDER_HISTORY_END,
            trd_env=TrdEnv.REAL,
            order_market=TrdMarket.NONE
        )
    finally:
        trd_ctx.close()

    if ret != RET_OK:
        return {
            "ok": False,
            "error": str(data),
            "source": "history_order_list_query_fallback",
            "orders": []
        }

    return {
        "ok": True,
        "source": "history_order_list_query_fallback",
        "orders": [
            order for order in frame_to_orders(data)
            if is_open_order(order)
        ]
    }


def cache_open_orders(result):
    global _open_orders_cache, _open_orders_cache_time
    now = time_module.time()
    _open_orders_cache_time = now
    _open_orders_cache = {
        "updated_at": time_module.strftime("%Y-%m-%dT%H:%M:%SZ", time_module.gmtime(now)),
        "source": result.get("source"),
        "orders": result.get("orders", []),
    }


def open_orders_cache_response():
    age_seconds = max(0.0, time_module.time() - _open_orders_cache_time)
    orders = _open_orders_cache.get("orders", [])
    return {
        "ok": True,
        "cached": True,
        "cache_age_seconds": round(age_seconds, 3),
        "updated_at": _open_orders_cache.get("updated_at"),
        "source": _open_orders_cache.get("source"),
        "count": len(orders),
        "orders": orders,
    }


def fresh_open_orders_response(result):
    orders = result.get("orders", [])
    return {
        "ok": result.get("ok", False),
        "cached": False,
        "cache_age_seconds": 0,
        "updated_at": _open_orders_cache.get("updated_at"),
        "source": result.get("source"),
        "count": len(orders),
        "orders": orders,
        **({"error": result.get("error")} if result.get("error") else {}),
    }


@router.get("/orders/open")
def get_open_orders(code: str = "", force: bool = False):
    with _open_orders_lock:
        if (
            not force
            and _open_orders_cache_time
            and time_module.time() - _open_orders_cache_time < OPEN_ORDERS_CACHE_TTL_SECONDS
        ):
            return open_orders_cache_response()

        result = query_current_open_orders(code=code)
        if result.get("ok") and not result.get("orders") and code in ("", OPEN_ORDER_HISTORY_CODE):
            fallback = query_known_sidu_open_order()
            if fallback.get("ok") and fallback.get("orders"):
                result = fallback

        if result.get("ok"):
            cache_open_orders(result)

        return fresh_open_orders_response(result)


@router.get("/open_orders")
def get_open_orders_legacy(code: str = "", force: bool = False):
    return get_open_orders(code=code, force=force)


@router.get("/orders/history")
def get_history_orders(
    code: str = "",
    start: str = "",
    end: str = "",
    status: list[str] | None = FastAPIQuery(default=None),
):
    trd_ctx = create_trade_context()
    try:
        ret, data = trd_ctx.history_order_list_query(
            status_filter_list=status or [],
            code=code,
            start=start,
            end=end,
            trd_env=TrdEnv.REAL,
            order_market=TrdMarket.NONE
        )
    finally:
        trd_ctx.close()

    if ret != RET_OK:
        return {
            "ok": False,
            "error": str(data),
            "orders": []
        }

    orders = frame_to_orders(data)
    return {
        "ok": True,
        "count": len(orders),
        "orders": orders
    }


@router.get("/history_orders")
def get_history_orders_legacy(
    code: str = "",
    start: str = "",
    end: str = "",
    status: list[str] | None = FastAPIQuery(default=None),
):
    return get_history_orders(code=code, start=start, end=end, status=status)


@router.get("/deals/history")
def get_history_deals(
    code: str = "",
    start: str = "",
    end: str = "",
):
    trd_ctx = create_trade_context()
    try:
        ret, data = trd_ctx.history_deal_list_query(
            code=code,
            start=start,
            end=end,
            trd_env=TrdEnv.REAL,
            deal_market=TrdMarket.NONE
        )
    finally:
        trd_ctx.close()

    if ret != RET_OK:
        return {
            "ok": False,
            "error": str(data),
            "deals": []
        }

    deals = frame_to_deals(data)
    return {
        "ok": True,
        "count": len(deals),
        "deals": deals
    }


@router.get("/history_deals")
def get_history_deals_legacy(
    code: str = "",
    start: str = "",
    end: str = "",
):
    return get_history_deals(code=code, start=start, end=end)


@router.get("/deals")
def get_cached_deals():
    cache = load_deal_cache()
    deals = cache.get("deals", [])
    return {
        "ok": True,
        "updated_at": cache.get("updated_at"),
        "count": len(deals),
        "deals": deals
    }


@router.post("/deals/sync_known_history")
def sync_known_history(force: bool = False):
    return sync_known_history_deals(force=force)
