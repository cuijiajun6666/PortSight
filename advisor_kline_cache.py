import json
import os
import threading
import time
from datetime import datetime, timezone

import pandas as pd
from moomoo import *

from config import DATA_DIR, HOST, PORT


KLINE_DIR = DATA_DIR / "klines"
KLINE_DIR.mkdir(parents=True, exist_ok=True)

KLINE_QUOTA_FILE = DATA_DIR / "kline_quota_usage.json"
DEFAULT_KLINE_START = os.getenv("ADVISOR_KLINE_START", "2023-01-01")
KLINE_QUOTA_LIMIT = int(os.getenv("ADVISOR_KLINE_QUOTA_LIMIT", "1000"))
KLINE_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_KLINE_REQUEST_INTERVAL_SECONDS", "0.55"))
KLINE_AUTYPE = AuType.NONE
KLINE_AUTYPE_NAME = "NONE"

_cache_lock = threading.RLock()
_rate_limit_lock = threading.RLock()
_last_kline_request_at = 0.0


def utc_now_iso():
    return datetime.now(timezone.utc).isoformat()


def symbol_file(code, period="day"):
    safe_code = code.replace("/", "_").replace(":", "_")
    period_dir = KLINE_DIR / period
    period_dir.mkdir(parents=True, exist_ok=True)
    return period_dir / f"{safe_code}.json"


def kltype_for_period(period):
    if period == "week":
        return KLType.K_WEEK
    if period == "month":
        month_type = getattr(KLType, "K_MON", None)
        if month_type is None:
            month_type = getattr(KLType, "K_MONTH")
        return month_type
    return KLType.K_DAY


def read_json(path, default):
    try:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)
    except FileNotFoundError:
        return default
    except json.JSONDecodeError:
        broken = path.with_suffix(f".broken-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}.json")
        path.replace(broken)
        return default


def atomic_write_json(path, payload):
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")
    os.replace(tmp_path, path)


def load_quota_usage():
    return read_json(KLINE_QUOTA_FILE, {"updated_at": None, "symbols": {}})


def save_quota_usage(usage):
    usage["updated_at"] = utc_now_iso()
    atomic_write_json(KLINE_QUOTA_FILE, usage)


def quota_symbols_in_window(usage):
    cutoff = pd.Timestamp.now(tz="UTC") - pd.Timedelta(days=7)
    active = {}
    for code, fetched_at in usage.get("symbols", {}).items():
        try:
            if pd.Timestamp(fetched_at) >= cutoff:
                active[code] = fetched_at
        except Exception:
            continue
    usage["symbols"] = active
    return active


def note_quota_usage(code):
    usage = load_quota_usage()
    active = quota_symbols_in_window(usage)
    if code not in active and len(active) >= KLINE_QUOTA_LIMIT:
        raise RuntimeError(f"历史K线额度可能不足: 最近7天已请求 {len(active)} 只股票")
    usage["symbols"][code] = utc_now_iso()
    save_quota_usage(usage)


def wait_for_kline_rate_limit():
    global _last_kline_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = KLINE_REQUEST_INTERVAL_SECONDS - (now - _last_kline_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_kline_request_at = time.monotonic()


def load_cached_klines(code, period="day"):
    payload = read_json(symbol_file(code, period=period), {"code": code, "period": period, "rows": []})
    rows = payload.get("rows", [])
    if not rows:
        return payload, pd.DataFrame()
    frame = pd.DataFrame(rows)
    if "time_key" in frame.columns:
        frame["date"] = pd.to_datetime(frame["time_key"]).dt.date.astype(str)
    elif "date" in frame.columns:
        frame["date"] = pd.to_datetime(frame["date"]).dt.date.astype(str)
    for column in ["open", "high", "low", "close", "volume", "turnover"]:
        if column in frame.columns:
            frame[column] = pd.to_numeric(frame[column], errors="coerce")
    return payload, frame.sort_values("date")


def frame_to_rows(frame):
    rows = []
    for _, row in frame.iterrows():
        record = {}
        for key, value in row.to_dict().items():
            try:
                if value != value:
                    value = None
            except Exception:
                pass
            if hasattr(value, "item"):
                value = value.item()
            record[key] = value
        if "date" not in record:
            record["date"] = str(record.get("time_key", ""))[:10]
        rows.append(record)
    return rows


def normalize_kline_frame(data):
    frame = data.copy()
    if "time_key" in frame.columns:
        frame["date"] = pd.to_datetime(frame["time_key"]).dt.date.astype(str)
    elif "date" not in frame.columns:
        frame["date"] = pd.to_datetime(frame.index).date.astype(str)
    for column in ["open", "high", "low", "close", "volume", "turnover"]:
        if column not in frame.columns:
            frame[column] = 0
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    keep = ["date", "time_key", "open", "high", "low", "close", "volume", "turnover"]
    keep = [column for column in keep if column in frame.columns]
    return frame[keep].dropna(subset=["close"]).sort_values("date")


def should_refresh(payload, force=False):
    if force:
        return True
    if payload.get("autype") != KLINE_AUTYPE_NAME:
        return True
    rows = payload.get("rows", [])
    if not rows:
        return True
    fetched_at = payload.get("fetched_at")
    if not fetched_at:
        return True
    try:
        fetched_day = pd.Timestamp(fetched_at).tz_convert("UTC").date()
    except Exception:
        fetched_day = pd.Timestamp(fetched_at).date()
    return fetched_day < datetime.now(timezone.utc).date()


def request_klines(code, start=None, end=None, period="day"):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    frames = []
    page_req_key = None
    try:
        while True:
            if page_req_key is None:
                wait_for_kline_rate_limit()
            ret, data, page_req_key = quote_ctx.request_history_kline(
                code,
                start=start or DEFAULT_KLINE_START,
                end=end,
                ktype=kltype_for_period(period),
                autype=KLINE_AUTYPE,
                max_count=1000,
                page_req_key=page_req_key,
            )
            if ret != RET_OK:
                raise RuntimeError(f"request_history_kline failed for {code}: {data}")
            frames.append(normalize_kline_frame(data))
            if page_req_key is None:
                break
    finally:
        quote_ctx.close()

    note_quota_usage(code)
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True).drop_duplicates(subset=["date"]).sort_values("date")


def sync_klines(code, start=None, end=None, period="day", force=False):
    with _cache_lock:
        payload, cached = load_cached_klines(code, period=period)
        if not should_refresh(payload, force=force):
            return {
                "ok": True,
                "synced": False,
                "source": "cache",
                "code": code,
                "period": period,
                "rows": len(cached),
                "latest_date": None if cached.empty else str(cached.iloc[-1]["date"]),
            }

        fresh = request_klines(code, start=start, end=end, period=period)
        rows = frame_to_rows(fresh)
        atomic_write_json(symbol_file(code, period=period), {
            "code": code,
            "period": period,
            "autype": KLINE_AUTYPE_NAME,
            "fetched_at": utc_now_iso(),
            "start": start or DEFAULT_KLINE_START,
            "end": end,
            "rows": rows,
        })
        return {
            "ok": True,
            "synced": True,
            "source": "moomoo",
            "code": code,
            "period": period,
            "rows": len(rows),
            "latest_date": rows[-1]["date"] if rows else None,
        }


def sync_daily_klines(code, start=None, end=None, force=False):
    return sync_klines(code, start=start, end=end, period="day", force=force)


def get_daily_klines(code, force=False):
    sync_daily_klines(code, force=force)
    _, frame = load_cached_klines(code)
    return frame


def sync_all_period_klines(code, start=None, end=None, force=False):
    return [
        sync_klines(code, start=start, end=end, period=period, force=force)
        for period in ("day", "week", "month")
    ]


def get_period_klines(code, period="day", force=False):
    sync_klines(code, period=period, force=force)
    _, frame = load_cached_klines(code, period=period)
    return frame
