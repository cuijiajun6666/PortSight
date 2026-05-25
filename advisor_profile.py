import json
import os
import threading
import time
from datetime import datetime, timezone

from moomoo import *

from config import DATA_DIR, HOST, PORT


OWNER_PLATE_FILE = DATA_DIR / "advisor_owner_plates.json"
VALUATION_FILE = DATA_DIR / "advisor_valuations.json"
OWNER_PLATE_REFRESH_SECONDS = int(os.getenv("ADVISOR_OWNER_PLATE_REFRESH_SECONDS", "86400"))
VALUATION_REFRESH_SECONDS = int(os.getenv("ADVISOR_VALUATION_REFRESH_SECONDS", "86400"))
OWNER_PLATE_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_OWNER_PLATE_REQUEST_INTERVAL_SECONDS", "3.2"))
VALUATION_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_VALUATION_REQUEST_INTERVAL_SECONDS", "1.1"))
OWNER_PLATE_BATCH_SIZE = 200

_owner_plate_lock = threading.RLock()
_valuation_lock = threading.RLock()
_rate_limit_lock = threading.RLock()
_last_owner_plate_request_at = 0.0
_last_valuation_request_at = 0.0


def utc_now_iso():
    return datetime.now(timezone.utc).isoformat()


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


def load_owner_plate_cache():
    return read_json(OWNER_PLATE_FILE, {"updated_at": None, "symbols": {}})


def save_owner_plate_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(OWNER_PLATE_FILE, cache)


def load_valuation_cache():
    return read_json(VALUATION_FILE, {"updated_at": None, "symbols": {}})


def save_valuation_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(VALUATION_FILE, cache)


def cache_is_fresh(symbol_payload, ttl_seconds):
    fetched_at = symbol_payload.get("fetched_at")
    if not fetched_at:
        return False
    try:
        age = datetime.now(timezone.utc) - datetime.fromisoformat(fetched_at)
        return age.total_seconds() < ttl_seconds
    except Exception:
        return False


def wait_for_owner_plate_rate_limit():
    global _last_owner_plate_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = OWNER_PLATE_REQUEST_INTERVAL_SECONDS - (now - _last_owner_plate_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_owner_plate_request_at = time.monotonic()


def wait_for_valuation_rate_limit():
    global _last_valuation_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = VALUATION_REQUEST_INTERVAL_SECONDS - (now - _last_valuation_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_valuation_request_at = time.monotonic()


def json_value(value):
    try:
        if value != value:
            return None
    except Exception:
        pass
    if hasattr(value, "item"):
        value = value.item()
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_value(item) for item in value]
    return str(value) if not isinstance(value, (str, int, float, bool, type(None))) else value


def frame_to_plate_map(data):
    result = {}
    for _, row in data.iterrows():
        code = str(row.get("code", ""))
        result.setdefault(code, []).append({
            "code": code,
            "name": json_value(row.get("name")),
            "plate_code": json_value(row.get("plate_code")),
            "plate_name": json_value(row.get("plate_name")),
            "plate_type": json_value(row.get("plate_type")),
        })
    return result


def request_owner_plates(codes):
    if not codes:
        return {}

    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_owner_plate_rate_limit()
        ret, data = quote_ctx.get_owner_plate(codes)
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_owner_plate failed: {data}")
    return frame_to_plate_map(data)


def sync_owner_plates(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _owner_plate_lock:
        cache = load_owner_plate_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], OWNER_PLATE_REFRESH_SECONDS)
        ]

        results = []
        for start in range(0, len(missing), OWNER_PLATE_BATCH_SIZE):
            batch = missing[start:start + OWNER_PLATE_BATCH_SIZE]
            if not batch:
                continue
            plate_map = request_owner_plates(batch)
            fetched_at = utc_now_iso()
            for code in batch:
                symbols[code] = {
                    "fetched_at": fetched_at,
                    "plates": plate_map.get(code, []),
                }
                results.append({
                    "ok": True,
                    "code": code,
                    "plates": len(plate_map.get(code, [])),
                    "source": "moomoo",
                })

        save_owner_plate_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": True,
                    "code": code,
                    "plates": len(symbols.get(code, {}).get("plates", [])),
                    "source": "cache",
                })

        return {
            "ok": True,
            "count": len(results),
            "results": results,
        }


def get_owner_plates(codes, force=False):
    sync_owner_plates(codes, force=force)
    cache = load_owner_plate_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("plates", [])
        for code in codes
    }


def summarize_valuation(data):
    trend = json_value(data.get("trend", {}))
    market_distribution = json_value(data.get("market_distribution", {}))
    plate_distribution = json_value(data.get("plate_distribution", {}))
    profit_growth_rate = json_value(data.get("profit_growth_rate", {}))
    return {
        "valuation_type": json_value(data.get("valuation_type")),
        "last_update_time": json_value(data.get("last_update_time")),
        "last_update_time_str": json_value(data.get("last_update_time_str")),
        "trend": {
            "current_value": trend.get("current_value"),
            "average_value": trend.get("average_value"),
            "avg_minus_1_stddev": trend.get("avg_minus_1_stddev"),
            "avg_plus_1_stddev": trend.get("avg_plus_1_stddev"),
            "valuation_percentile": trend.get("valuation_percentile"),
            "forward_value": trend.get("forward_value"),
        },
        "market_distribution": {
            "total": market_distribution.get("total"),
            "ranking": market_distribution.get("ranking"),
            "average_value": market_distribution.get("average_value"),
            "median_value": market_distribution.get("median_value"),
        },
        "plate_distribution": {
            "plate": plate_distribution.get("plate"),
            "plate_name": plate_distribution.get("plate_name"),
            "plate_average_value": plate_distribution.get("plate_average_value"),
            "plate_ranking": plate_distribution.get("plate_ranking"),
            "plate_stock_item_count": plate_distribution.get("plate_stock_item_count"),
        },
        "profit_growth_rate": {
            "financial_ttm_multiple": profit_growth_rate.get("financial_ttm_multiple"),
            "market_cap_multiple": profit_growth_rate.get("market_cap_multiple"),
            "year_count": profit_growth_rate.get("year_count"),
            "conclusion_detailed": profit_growth_rate.get("conclusion_detailed"),
        },
    }


def request_valuation(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_valuation_rate_limit()
        ret, data = quote_ctx.get_valuation_detail(code)
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_valuation_detail failed for {code}: {data}")
    return summarize_valuation(data)


def sync_valuations(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _valuation_lock:
        cache = load_valuation_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], VALUATION_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "valuation": request_valuation(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "valuation": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_valuation_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("valuation") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_valuations(codes, force=False):
    sync_valuations(codes, force=force)
    cache = load_valuation_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("valuation")
        for code in codes
    }
