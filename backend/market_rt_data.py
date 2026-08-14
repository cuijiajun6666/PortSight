from __future__ import annotations

import argparse
import json
import math
import os
import threading
import time
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pandas as pd
import pandas_market_calendars as mcal
from moomoo import *

from config import DATA_DIR, HOST, PORT


MARKET_CODE_ALIASES = {
    "SPX": "US.SPY",
    ".SPX": "US.SPY",
    "US.SPX": "US.SPY",
    "US..SPX": "US.SPY",
    "IXIC": "US.QQQ",
    ".IXIC": "US.QQQ",
    "US.IXIC": "US.QQQ",
    "US..IXIC": "US.QQQ",
    "DJI": "US.DIA",
    ".DJI": "US.DIA",
    "US.DJI": "US.DIA",
    "US..DJI": "US.DIA",
}
DEFAULT_MARKET_CODES = ["US.SPY", "US.QQQ", "US.DIA"]
REAL_INDEX_BY_CHART_CODE = {
    "US.SPY": "US..SPX",
    "US.QQQ": "US..IXIC",
    "US.DIA": "US..DJI",
}
MARKET_INTRADAY_FILE = DATA_DIR / "market_intraday_cache.json"
CACHE_LOCK = threading.RLock()
NY_TZ = ZoneInfo("America/New_York")
NYSE = mcal.get_calendar("NYSE")


class MarketRTDataHandler(RTDataHandlerBase):
    """Collect RT_DATA push packets while a market is open."""

    def __init__(self):
        super().__init__()
        self.latest_by_code: dict[str, pd.DataFrame] = {}

    def on_recv_rsp(self, rsp_pb):
        ret_code, data = super(MarketRTDataHandler, self).on_recv_rsp(rsp_pb)
        if ret_code != RET_OK:
            print(f"MarketRTDataHandler error: {data}")
            return RET_ERROR, data

        if not data.empty and "code" in data.columns:
            for code, frame in data.groupby("code"):
                self.latest_by_code[str(code)] = frame.copy()
        return RET_OK, data


def normalize_codes(codes: list[str] | tuple[str, ...] | None = None) -> list[str]:
    if not codes:
        return DEFAULT_MARKET_CODES.copy()
    normalized = []
    for code in codes:
        code = code.strip().upper()
        if code in MARKET_CODE_ALIASES:
            normalized.append(MARKET_CODE_ALIASES[code])
        else:
            normalized.append(code if "." in code else f"US.{code}")
    return normalized


def _schedule_for_day(day: date) -> pd.DataFrame:
    return NYSE.schedule(start_date=day.isoformat(), end_date=day.isoformat())


def is_us_market_open(now: datetime | None = None) -> bool:
    now = now or datetime.now(NY_TZ)
    now_utc = now.astimezone(ZoneInfo("UTC"))
    schedule = _schedule_for_day(now.astimezone(NY_TZ).date())
    if schedule.empty:
        return False

    market_open = schedule.iloc[0]["market_open"].to_pydatetime()
    market_close = schedule.iloc[0]["market_close"].to_pydatetime()
    return market_open <= now_utc <= market_close


def latest_closed_trading_day(now: datetime | None = None) -> date:
    now = now or datetime.now(NY_TZ)
    now_utc = now.astimezone(ZoneInfo("UTC"))
    today = now.astimezone(NY_TZ).date()
    lookback_start = today - timedelta(days=14)
    schedule = NYSE.schedule(
        start_date=lookback_start.isoformat(),
        end_date=today.isoformat(),
    )
    closed_schedule = schedule[schedule["market_close"] <= now_utc]
    if closed_schedule.empty:
        raise RuntimeError("No closed NYSE trading day found in the last 14 days.")
    return closed_schedule.index[-1].date()


def target_trading_day(now: datetime | None = None) -> date:
    now = now or datetime.now(NY_TZ)
    today = now.astimezone(NY_TZ).date()
    now_utc = now.astimezone(ZoneInfo("UTC"))
    schedule = _schedule_for_day(today)
    if not schedule.empty and now_utc >= schedule.iloc[0]["market_open"].to_pydatetime():
        return today
    return latest_closed_trading_day(now)


def _opened_mins_from_time(time_value: str) -> int | None:
    try:
        parsed = datetime.strptime(str(time_value), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    return parsed.hour * 60 + parsed.minute


def _history_kline_to_rt_shape(data: pd.DataFrame) -> pd.DataFrame:
    if data.empty:
        return data

    result = pd.DataFrame()
    result["code"] = data.get("code", "")
    result["name"] = data.get("name", "")
    result["time"] = data.get("time_key", "")
    result["is_blank"] = False
    result["opened_mins"] = result["time"].map(_opened_mins_from_time)
    result["cur_price"] = data.get("close")
    result["last_close"] = data.get("last_close")
    result["avg_price"] = None
    result["volume"] = data.get("volume")
    result["turnover"] = data.get("turnover")
    return result


def load_intraday_cache() -> dict:
    with CACHE_LOCK:
        if not os.path.exists(MARKET_INTRADAY_FILE):
            return {"updated_at": None, "dates": {}, "completed_dates": {}}
        try:
            with open(MARKET_INTRADAY_FILE, "r") as f:
                cache = json.load(f)
        except json.JSONDecodeError as exc:
            broken_file = MARKET_INTRADAY_FILE.with_suffix(
                f".broken-{datetime.now(ZoneInfo('UTC')).strftime('%Y%m%d%H%M%S')}.json"
            )
            os.replace(MARKET_INTRADAY_FILE, broken_file)
            print(f"大盘分时缓存 JSON 损坏，已隔离: {broken_file} ({exc})")
            return {"updated_at": None, "dates": {}, "completed_dates": {}}
    cache.setdefault("dates", {})
    cache.setdefault("completed_dates", {})
    return cache


def save_intraday_cache(cache: dict):
    with CACHE_LOCK:
        cache["updated_at"] = datetime.now(ZoneInfo("UTC")).isoformat()
        tmp_file = MARKET_INTRADAY_FILE.with_suffix(".tmp")
        with open(tmp_file, "w") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2, allow_nan=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_file, MARKET_INTRADAY_FILE)


def prune_intraday_cache(cache: dict, keep_date: date) -> dict:
    keep_key = keep_date.isoformat()
    cache["dates"] = {
        date_key: data
        for date_key, data in cache.get("dates", {}).items()
        if date_key == keep_key
    }
    cache["completed_dates"] = {
        date_key: data
        for date_key, data in cache.get("completed_dates", {}).items()
        if date_key == keep_key
    }
    return cache


def _json_value(value):
    if pd.isna(value):
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    if hasattr(value, "item"):
        return value.item()
    return value


def _safe_float(value):
    if value is None or pd.isna(value):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _frame_to_records(frame: pd.DataFrame) -> list[dict]:
    if frame.empty:
        return []
    safe_frame = frame.where(pd.notna(frame), None)
    return [
        {key: _json_value(value) for key, value in record.items()}
        for record in safe_frame.to_dict(orient="records")
    ]


def _merge_records(existing: list[dict], incoming: list[dict]) -> list[dict]:
    by_time = {
        record.get("time"): record
        for record in existing
        if record.get("time")
    }
    for record in incoming:
        time_key = record.get("time")
        if time_key:
            by_time[time_key] = record
    return [by_time[key] for key in sorted(by_time)]


def upsert_intraday_frames(
    trading_day: date,
    frames: dict[str, pd.DataFrame],
    mark_complete: bool = False,
    prune_before_save: bool = False,
) -> dict:
    with CACHE_LOCK:
        cache = load_intraday_cache()
        if prune_before_save:
            cache = prune_intraday_cache(cache, trading_day)

        date_key = trading_day.isoformat()
        cache.setdefault("dates", {}).setdefault(date_key, {})
        cache.setdefault("completed_dates", {}).setdefault(date_key, {})

        for code, frame in frames.items():
            incoming = _frame_to_records(frame)
            existing = cache["dates"][date_key].get(code, [])
            cache["dates"][date_key][code] = _merge_records(existing, incoming)
            if mark_complete:
                cache["completed_dates"][date_key][code] = True

        save_intraday_cache(cache)
        return cache


def get_cached_intraday(trading_day: date, codes: list[str]) -> dict[str, list[dict]]:
    cache = load_intraday_cache()
    date_cache = cache.get("dates", {}).get(trading_day.isoformat(), {})
    return {code: date_cache.get(code, []) for code in codes}


def _fetch_quote_summary(codes: list[str]) -> dict[str, dict]:
    quote_codes = list({
        REAL_INDEX_BY_CHART_CODE.get(code, code)
        for code in codes
    })
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        ret, msg = quote_ctx.subscribe(
            quote_codes,
            [SubType.QUOTE],
            subscribe_push=False,
            extended_time=True,
        )
        if ret != RET_OK:
            raise RuntimeError(f"subscribe QUOTE failed: {msg}")

        ret, quote_data = quote_ctx.get_stock_quote(quote_codes)
        if ret != RET_OK:
            raise RuntimeError(f"get_stock_quote failed: {quote_data}")
    finally:
        quote_ctx.close()

    quote_by_code = {}
    for _, row in quote_data.iterrows():
        quote_code = str(row.get("code", ""))
        price = _safe_float(row.get("last_price"))
        previous_close = _safe_float(row.get("prev_close_price"))
        if previous_close is None:
            previous_close = _safe_float(row.get("last_close_price"))
        change = None
        change_percent = None
        if price is not None and previous_close not in (None, 0):
            change = price - previous_close
            change_percent = change / previous_close * 100

        quote_by_code[quote_code] = {
            "quote_code": quote_code,
            "name": str(row.get("name", "")),
            "price": price,
            "previous_close": previous_close,
            "change": change,
            "change_percent": change_percent,
            "latest_time": " ".join(
                part for part in [
                    str(row.get("data_date", "") or ""),
                    str(row.get("data_time", "") or ""),
                ]
                if part
            ) or None,
        }
    return quote_by_code


def build_intraday_summary(
    data: dict[str, list[dict]],
    quote_summary: dict[str, dict] | None = None,
) -> dict[str, dict]:
    quote_summary = quote_summary or {}
    summary = {}
    for code, rows in data.items():
        valid_rows = [row for row in rows if row.get("cur_price") is not None]
        latest = valid_rows[-1] if valid_rows else None
        previous_close = latest.get("last_close") if latest else None
        price = latest.get("cur_price") if latest else None
        change = None
        change_percent = None
        if price is not None and previous_close not in (None, 0):
            change = price - previous_close
            change_percent = change / previous_close * 100

        quote_code = REAL_INDEX_BY_CHART_CODE.get(code, code)
        real_quote = quote_summary.get(quote_code)
        if real_quote:
            price = real_quote["price"]
            previous_close = real_quote["previous_close"]
            change = real_quote["change"]
            change_percent = real_quote["change_percent"]

        summary[code] = {
            "code": code,
            "chart_code": code,
            "quote_code": quote_code,
            "name": real_quote.get("name") if real_quote else (latest.get("name") if latest else ""),
            "price": price,
            "previous_close": previous_close,
            "change": change,
            "change_percent": change_percent,
            "latest_time": real_quote.get("latest_time") if real_quote else (latest.get("time") if latest else None),
            "points": len(rows),
        }
    return summary


def _cache_is_complete(trading_day: date, codes: list[str]) -> bool:
    cache = load_intraday_cache()
    date_key = trading_day.isoformat()
    completed = cache.get("completed_dates", {}).get(date_key, {})
    cached = cache.get("dates", {}).get(date_key, {})
    return all(completed.get(code) is True and len(cached.get(code, [])) > 0 for code in codes)


def _fetch_realtime_rt_data(quote_ctx: OpenQuoteContext, codes: list[str]) -> dict[str, pd.DataFrame]:
    ret, msg = quote_ctx.subscribe(
        codes,
        [SubType.RT_DATA],
        session=Session.ALL,
    )
    if ret != RET_OK:
        raise RuntimeError(f"subscribe RT_DATA failed: {msg}")

    frames: dict[str, pd.DataFrame] = {}
    for code in codes:
        ret, data = quote_ctx.get_rt_data(code)
        if ret != RET_OK:
            raise RuntimeError(f"get_rt_data failed for {code}: {data}")
        frames[code] = data
    return frames


def _fetch_history_minute_data(
    quote_ctx: OpenQuoteContext,
    codes: list[str],
    trading_day: date,
) -> dict[str, pd.DataFrame]:
    frames: dict[str, pd.DataFrame] = {}
    day_str = trading_day.isoformat()
    for code in codes:
        ret, data, _ = quote_ctx.request_history_kline(
            code,
            start=day_str,
            end=day_str,
            ktype=KLType.K_1M,
            autype=AuType.NONE,
            max_count=None,
            extended_time=False,
            session=Session.RTH,
        )
        if ret != RET_OK:
            raise RuntimeError(f"request_history_kline failed for {code}: {data}")
        frames[code] = _history_kline_to_rt_shape(data)
    return frames


def sync_market_intraday_cache(
    codes: list[str] | tuple[str, ...] | None = None,
    force_closed_backfill: bool = False,
) -> dict:
    codes = normalize_codes(codes)
    open_now = is_us_market_open()
    trading_day = target_trading_day()

    if not open_now and not force_closed_backfill and _cache_is_complete(trading_day, codes):
        return {
            "ok": True,
            "synced": False,
            "source": "cache",
            "market_open": False,
            "trading_date": trading_day.isoformat(),
            "codes": codes,
        }

    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        frames = (
            _fetch_realtime_rt_data(quote_ctx, codes)
            if open_now
            else _fetch_history_minute_data(quote_ctx, codes, trading_day)
        )
    finally:
        quote_ctx.close()

    upsert_intraday_frames(
        trading_day,
        frames,
        mark_complete=not open_now,
        prune_before_save=True,
    )

    return {
        "ok": True,
        "synced": True,
        "source": "realtime_rt_data" if open_now else "closed_day_1m_kline",
        "market_open": open_now,
        "trading_date": trading_day.isoformat(),
        "codes": codes,
    }


def fetch_market_intraday(codes: list[str] | tuple[str, ...] | None = None) -> dict:
    codes = normalize_codes(codes)
    try:
        sync_info = sync_market_intraday_cache(codes)
    except Exception as exc:
        trading_day = target_trading_day()
        data = get_cached_intraday(trading_day, codes)
        try:
            quote_summary = _fetch_quote_summary(codes)
        except Exception:
            quote_summary = {}
        if any(data.values()):
            return {
                "ok": True,
                "source": "cache_stale",
                "market_open": is_us_market_open(),
                "trading_date": trading_day.isoformat(),
                "refresh_interval_seconds": 60 if is_us_market_open() else None,
                "codes": codes,
                "cache_file": MARKET_INTRADAY_FILE,
                "error": str(exc),
                "summary": build_intraday_summary(data, quote_summary),
                "data": data,
            }
        raise

    trading_day = date.fromisoformat(sync_info["trading_date"])
    data = get_cached_intraday(trading_day, codes)
    try:
        quote_summary = _fetch_quote_summary(codes)
        quote_error = None
    except Exception as exc:
        quote_summary = {}
        quote_error = str(exc)

    result = {
        "ok": True,
        "source": sync_info["source"],
        "market_open": sync_info["market_open"],
        "trading_date": sync_info["trading_date"],
        "refresh_interval_seconds": 60 if sync_info["market_open"] else None,
        "codes": codes,
        "cache_file": MARKET_INTRADAY_FILE,
        "summary": build_intraday_summary(data, quote_summary),
        "data": data,
    }
    if quote_error:
        result["quote_error"] = quote_error
    return result


def watch_realtime_market(
    codes: list[str] | tuple[str, ...] | None = None,
    seconds: int = 15,
) -> MarketRTDataHandler:
    codes = normalize_codes(codes)
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    handler = MarketRTDataHandler()
    try:
        quote_ctx.set_handler(handler)
        ret, msg = quote_ctx.subscribe(
            codes,
            [SubType.RT_DATA],
            session=Session.ALL,
        )
        if ret != RET_OK:
            raise RuntimeError(f"subscribe RT_DATA failed: {msg}")
        time.sleep(seconds)
        return handler
    finally:
        quote_ctx.close()


def _frames_to_records(frames: dict[str, pd.DataFrame]) -> dict[str, list[dict]]:
    return {code: _frame_to_records(frame) for code, frame in frames.items()}


def main():
    parser = argparse.ArgumentParser(description="Fetch US market intraday data.")
    parser.add_argument(
        "codes",
        nargs="*",
        help="Market proxy codes, for example SPX IXIC DJI or SPY QQQ DIA. Index aliases use ETF proxies.",
    )
    parser.add_argument("--watch", type=int, default=0, help="Listen to RT_DATA pushes for N seconds.")
    args = parser.parse_args()

    if args.watch > 0:
        handler = watch_realtime_market(args.codes, args.watch)
        payload = {
            "ok": True,
            "source": "realtime_rt_data_push",
            "codes": normalize_codes(args.codes),
            "data": _frames_to_records(handler.latest_by_code),
        }
    else:
        result = fetch_market_intraday(args.codes)
        payload = result

    print(json.dumps(payload, ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    main()
