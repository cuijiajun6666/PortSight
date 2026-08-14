import json
import os
import threading
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from moomoo import *

from config import DATA_DIR, HOST, PORT


DEALS_FILE = DATA_DIR / "trade_deals.json"
DEALS_LOCK = threading.RLock()
KNOWN_DEAL_DATES = [
    "2025-12-23",
    "2025-12-24",
    "2025-12-26",
    "2025-12-29",
    "2025-12-30",
    "2026-01-02",
    "2026-01-05",
    "2026-01-06",
    "2026-01-07",
    "2026-01-08",
    "2026-01-13",
    "2026-01-14",
    "2026-01-15",
    "2026-01-16",
    "2026-01-21",
    "2026-01-23",
    "2026-01-24",
    "2026-01-26",
    "2026-01-27",
    "2026-02-04",
    "2026-03-03",
]

_deal_push_ctx = None


def normalize_date(value: str) -> str:
    value = value.strip().replace(".", "-")
    if len(value) == 8 and value.isdigit():
        return f"{value[:4]}-{value[4:6]}-{value[6:]}"
    return value


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


def frame_to_deals(data):
    deals = []
    for _, row in data.iterrows():
        record = {key: json_value(value) for key, value in row.to_dict().items()}
        record["deal_id"] = str(record.get("deal_id", ""))
        record["order_id"] = str(record.get("order_id", ""))
        deals.append(record)
    return deals


def load_deal_cache():
    with DEALS_LOCK:
        if not os.path.exists(DEALS_FILE):
            return {"updated_at": None, "synced_history_dates": [], "deals": []}
        try:
            with open(DEALS_FILE, "r") as f:
                cache = json.load(f)
        except json.JSONDecodeError:
            broken_file = DEALS_FILE.with_suffix(
                f".broken-{datetime.now(ZoneInfo('UTC')).strftime('%Y%m%d%H%M%S')}.json"
            )
            os.replace(DEALS_FILE, broken_file)
            print(f"成交缓存 JSON 损坏，已隔离: {broken_file}")
            return {"updated_at": None, "deals": []}
        cache.setdefault("deals", [])
        cache.setdefault("synced_history_dates", [])
        return cache


def save_deal_cache(cache):
    with DEALS_LOCK:
        cache["updated_at"] = datetime.now(ZoneInfo("UTC")).isoformat()
        tmp_file = DEALS_FILE.with_suffix(".tmp")
        with open(tmp_file, "w") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2, allow_nan=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_file, DEALS_FILE)


def upsert_deals(deals, cache=None, save: bool = True):
    with DEALS_LOCK:
        cache = cache or load_deal_cache()
        by_id = {
            str(deal.get("deal_id", "")): deal
            for deal in cache.get("deals", [])
            if deal.get("deal_id")
        }

        inserted = 0
        for deal in deals:
            deal_id = str(deal.get("deal_id", ""))
            if not deal_id:
                continue
            if deal_id not in by_id:
                inserted += 1
            by_id[deal_id] = deal

        cache["deals"] = sorted(
            by_id.values(),
            key=lambda item: str(item.get("create_time", "")),
            reverse=True
        )
        if save:
            save_deal_cache(cache)
        return inserted


def sync_known_history_deals(dates=None, sleep_seconds: float = 3.2, force: bool = False):
    dates = [normalize_date(date) for date in (dates or KNOWN_DEAL_DATES)]
    cache = load_deal_cache()
    synced_dates = set(cache.get("synced_history_dates", []))
    dates_to_query = dates if force else [day for day in dates if day not in synced_dates]

    if not dates_to_query:
        return {
            "ok": True,
            "skipped": True,
            "reason": "all_known_dates_already_synced",
            "known_dates": dates,
            "synced_history_dates": sorted(synced_dates),
            "missing_known_dates": [],
            "inserted": 0,
            "results": [],
            "cache": cache
        }

    trd_ctx = create_trade_context()
    results = []
    total_inserted = 0

    try:
        for index, day in enumerate(dates_to_query):
            ret, data = trd_ctx.history_deal_list_query(
                code="",
                start=day,
                end=day,
                trd_env=TrdEnv.REAL,
                deal_market=TrdMarket.NONE
            )

            if ret != RET_OK:
                results.append({"date": day, "ok": False, "error": str(data), "count": 0})
            else:
                deals = frame_to_deals(data)
                inserted = upsert_deals(deals, cache=cache, save=False)
                synced_dates.add(day)
                cache["synced_history_dates"] = sorted(synced_dates)
                total_inserted += inserted
                results.append({"date": day, "ok": True, "count": len(deals), "inserted": inserted})

            if index < len(dates_to_query) - 1:
                time.sleep(sleep_seconds)
    finally:
        trd_ctx.close()

    save_deal_cache(cache)
    missing_known_dates = [day for day in dates if day not in synced_dates]

    return {
        "ok": len(missing_known_dates) == 0,
        "known_dates": dates,
        "queried_dates": dates_to_query,
        "synced_history_dates": sorted(synced_dates),
        "missing_known_dates": missing_known_dates,
        "inserted": total_inserted,
        "results": results,
        "cache": load_deal_cache()
    }


class TradeDealCacheHandler(TradeDealHandlerBase):
    def on_recv_rsp(self, rsp_pb):
        ret, content = super().on_recv_rsp(rsp_pb)
        if ret == RET_OK:
            deals = frame_to_deals(content)
            inserted = upsert_deals(deals)
            print(f"成交推送已写入缓存: {inserted} new deal(s)")
        return ret, content


def start_deal_push_listener():
    global _deal_push_ctx
    if _deal_push_ctx is not None:
        return

    try:
        ctx = create_trade_context()
        ctx.set_handler(TradeDealCacheHandler())
        ctx.get_acc_list()
        _deal_push_ctx = ctx
        print("成交推送监听已启动")
    except Exception as exc:
        print(f"成交推送监听启动失败: {exc}")


def stop_deal_push_listener():
    global _deal_push_ctx
    if _deal_push_ctx is None:
        return
    try:
        _deal_push_ctx.close()
    finally:
        _deal_push_ctx = None
        print("成交推送监听已关闭")
