import json
import os
import threading
import time
from datetime import datetime, timezone

from moomoo import *

from config import DATA_DIR, HOST, PORT


OWNER_PLATE_FILE = DATA_DIR / "advisor_owner_plates.json"
VALUATION_FILE = DATA_DIR / "advisor_valuations.json"
FINANCIALS_FILE = DATA_DIR / "advisor_financials.json"
EARNINGS_MOVE_FILE = DATA_DIR / "advisor_earnings_moves.json"
COMPANY_PROFILE_FILE = DATA_DIR / "advisor_company_profiles.json"
OPERATIONAL_EFFICIENCY_FILE = DATA_DIR / "advisor_operational_efficiency.json"
CAPITAL_FLOW_FILE = DATA_DIR / "advisor_capital_flow.json"
CAPITAL_DISTRIBUTION_FILE = DATA_DIR / "advisor_capital_distribution.json"
OWNER_PLATE_REFRESH_SECONDS = int(os.getenv("ADVISOR_OWNER_PLATE_REFRESH_SECONDS", "86400"))
VALUATION_REFRESH_SECONDS = int(os.getenv("ADVISOR_VALUATION_REFRESH_SECONDS", "86400"))
FINANCIALS_REFRESH_SECONDS = int(os.getenv("ADVISOR_FINANCIALS_REFRESH_SECONDS", "86400"))
EARNINGS_MOVE_REFRESH_SECONDS = int(os.getenv("ADVISOR_EARNINGS_MOVE_REFRESH_SECONDS", "86400"))
COMPANY_PROFILE_REFRESH_SECONDS = int(os.getenv("ADVISOR_COMPANY_PROFILE_REFRESH_SECONDS", "604800"))
OPERATIONAL_EFFICIENCY_REFRESH_SECONDS = int(os.getenv("ADVISOR_OPERATIONAL_EFFICIENCY_REFRESH_SECONDS", "86400"))
CAPITAL_FLOW_REFRESH_SECONDS = int(os.getenv("ADVISOR_CAPITAL_FLOW_REFRESH_SECONDS", "86400"))
CAPITAL_DISTRIBUTION_REFRESH_SECONDS = int(os.getenv("ADVISOR_CAPITAL_DISTRIBUTION_REFRESH_SECONDS", "86400"))
OWNER_PLATE_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_OWNER_PLATE_REQUEST_INTERVAL_SECONDS", "3.2"))
VALUATION_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_VALUATION_REQUEST_INTERVAL_SECONDS", "1.1"))
FINANCIALS_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_FINANCIALS_REQUEST_INTERVAL_SECONDS", "1.1"))
EARNINGS_MOVE_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_EARNINGS_MOVE_REQUEST_INTERVAL_SECONDS", "1.1"))
COMPANY_PROFILE_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_COMPANY_PROFILE_REQUEST_INTERVAL_SECONDS", "1.1"))
OPERATIONAL_EFFICIENCY_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_OPERATIONAL_EFFICIENCY_REQUEST_INTERVAL_SECONDS", "1.1"))
CAPITAL_FLOW_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_CAPITAL_FLOW_REQUEST_INTERVAL_SECONDS", "1.1"))
CAPITAL_DISTRIBUTION_REQUEST_INTERVAL_SECONDS = float(os.getenv("ADVISOR_CAPITAL_DISTRIBUTION_REQUEST_INTERVAL_SECONDS", "1.1"))
OWNER_PLATE_BATCH_SIZE = 200
FINANCIALS_REPORT_COUNT = int(os.getenv("ADVISOR_FINANCIALS_REPORT_COUNT", "6"))
EARNINGS_MOVE_PERIOD_COUNT = int(os.getenv("ADVISOR_EARNINGS_MOVE_PERIOD_COUNT", "8"))
EARNINGS_HISTORY_MAX_ROWS = int(os.getenv("ADVISOR_EARNINGS_HISTORY_MAX_ROWS", "600"))
OPERATIONAL_EFFICIENCY_COUNT = int(os.getenv("ADVISOR_OPERATIONAL_EFFICIENCY_COUNT", "10"))
CAPITAL_FLOW_MAX_ROWS = int(os.getenv("ADVISOR_CAPITAL_FLOW_MAX_ROWS", "260"))
CAPITAL_FLOW_PERIOD = os.getenv("ADVISOR_CAPITAL_FLOW_PERIOD", "DAY")

_owner_plate_lock = threading.RLock()
_valuation_lock = threading.RLock()
_financials_lock = threading.RLock()
_earnings_move_lock = threading.RLock()
_company_profile_lock = threading.RLock()
_operational_efficiency_lock = threading.RLock()
_capital_flow_lock = threading.RLock()
_capital_distribution_lock = threading.RLock()
_rate_limit_lock = threading.RLock()
_last_owner_plate_request_at = 0.0
_last_valuation_request_at = 0.0
_last_financials_request_at = 0.0
_last_earnings_move_request_at = 0.0
_last_company_profile_request_at = 0.0
_last_operational_efficiency_request_at = 0.0
_last_capital_flow_request_at = 0.0
_last_capital_distribution_request_at = 0.0


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


def load_financials_cache():
    return read_json(FINANCIALS_FILE, {"updated_at": None, "symbols": {}})


def save_financials_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(FINANCIALS_FILE, cache)


def load_earnings_move_cache():
    return read_json(EARNINGS_MOVE_FILE, {"updated_at": None, "symbols": {}})


def save_earnings_move_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(EARNINGS_MOVE_FILE, cache)


def load_company_profile_cache():
    return read_json(COMPANY_PROFILE_FILE, {"updated_at": None, "symbols": {}})


def save_company_profile_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(COMPANY_PROFILE_FILE, cache)


def load_operational_efficiency_cache():
    return read_json(OPERATIONAL_EFFICIENCY_FILE, {"updated_at": None, "symbols": {}})


def save_operational_efficiency_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(OPERATIONAL_EFFICIENCY_FILE, cache)


def load_capital_flow_cache():
    return read_json(CAPITAL_FLOW_FILE, {"updated_at": None, "symbols": {}})


def save_capital_flow_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(CAPITAL_FLOW_FILE, cache)


def load_capital_distribution_cache():
    return read_json(CAPITAL_DISTRIBUTION_FILE, {"updated_at": None, "symbols": {}})


def save_capital_distribution_cache(cache):
    cache["updated_at"] = utc_now_iso()
    atomic_write_json(CAPITAL_DISTRIBUTION_FILE, cache)


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


def wait_for_financials_rate_limit():
    global _last_financials_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = FINANCIALS_REQUEST_INTERVAL_SECONDS - (now - _last_financials_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_financials_request_at = time.monotonic()


def wait_for_earnings_move_rate_limit():
    global _last_earnings_move_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = EARNINGS_MOVE_REQUEST_INTERVAL_SECONDS - (now - _last_earnings_move_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_earnings_move_request_at = time.monotonic()


def wait_for_company_profile_rate_limit():
    global _last_company_profile_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = COMPANY_PROFILE_REQUEST_INTERVAL_SECONDS - (now - _last_company_profile_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_company_profile_request_at = time.monotonic()


def wait_for_operational_efficiency_rate_limit():
    global _last_operational_efficiency_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = OPERATIONAL_EFFICIENCY_REQUEST_INTERVAL_SECONDS - (now - _last_operational_efficiency_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_operational_efficiency_request_at = time.monotonic()


def wait_for_capital_flow_rate_limit():
    global _last_capital_flow_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = CAPITAL_FLOW_REQUEST_INTERVAL_SECONDS - (now - _last_capital_flow_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_capital_flow_request_at = time.monotonic()


def wait_for_capital_distribution_rate_limit():
    global _last_capital_distribution_request_at
    with _rate_limit_lock:
        now = time.monotonic()
        wait_seconds = CAPITAL_DISTRIBUTION_REQUEST_INTERVAL_SECONDS - (now - _last_capital_distribution_request_at)
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        _last_capital_distribution_request_at = time.monotonic()


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


def frame_to_records(data, max_rows=None):
    records = []
    source = data.head(max_rows) if max_rows else data
    for _, row in source.iterrows():
        records.append({
            str(key): json_value(value)
            for key, value in row.to_dict().items()
        })
    return records


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


def compact_financial_report(report):
    items = []
    for item in report.get("item_list", []) or []:
        items.append({
            "field_id": json_value(item.get("field_id")),
            "display_name": json_value(item.get("display_name")),
            "data": json_value(item.get("data")),
            "yoy": json_value(item.get("yoy")),
            "qoq": json_value(item.get("qoq")),
        })
    return {
        "date_time": json_value(report.get("date_time")),
        "date_time_str": json_value(report.get("date_time_str")),
        "fiscal_year": json_value(report.get("fiscal_year")),
        "financial_type": json_value(report.get("financial_type")),
        "period_text": json_value(report.get("period_text")),
        "currency_info": json_value(report.get("currency_info")),
        "currency_code": json_value(report.get("currency_code")),
        "accounting_standards": json_value(report.get("accounting_standards")),
        "auditor_report": json_value(report.get("auditor_report")),
        "items": items,
    }


def summarize_financials(data):
    reports = data.get("report_list", []) or []
    structure = data.get("structure_list", []) or []
    return {
        "structure": [
            {
                "field_id": json_value(item.get("field_id")),
                "display_name": json_value(item.get("display_name")),
            }
            for item in structure
        ],
        "reports": [
            compact_financial_report(report)
            for report in reports[:FINANCIALS_REPORT_COUNT]
        ],
        "next_key": json_value(data.get("next_key")),
    }


def request_financials(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_financials_rate_limit()
        ret, data = quote_ctx.get_financials_statements(
            code,
            num=FINANCIALS_REPORT_COUNT,
        )
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_financials_statements failed for {code}: {data}")
    return summarize_financials(data)


def sync_financials(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _financials_lock:
        cache = load_financials_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], FINANCIALS_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "financials": request_financials(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "financials": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_financials_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("financials") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_financials(codes, force=False):
    sync_financials(codes, force=force)
    cache = load_financials_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("financials")
        for code in codes
    }


def pct_change(start, end):
    try:
        start = float(start)
        end = float(end)
        if start == 0:
            return None
        return end / start - 1
    except Exception:
        return None


def summarize_earnings_history(history_records):
    by_period = {}
    for row in history_records:
        key = f"{row.get('fiscal_year')}|{row.get('financial_type')}|{row.get('period_text')}"
        by_period.setdefault(key, []).append(row)

    returns_1d = []
    returns_5d = []
    pre_returns_5d = []
    max_abs_moves = []
    latest = None

    for rows in by_period.values():
        by_delta = {
            int(row.get("schedule_delta"))
            for row in rows
            if row.get("schedule_delta") is not None
        }
        row_by_delta = {
            int(row.get("schedule_delta")): row
            for row in rows
            if row.get("schedule_delta") is not None
        }
        event = row_by_delta.get(0)
        if not event:
            continue
        latest = latest or event
        event_close = event.get("close_price") or event.get("schedule_close_price")
        if 1 in by_delta:
            value = pct_change(event_close, row_by_delta[1].get("schedule_close_price"))
            if value is not None:
                returns_1d.append(value)
        if 5 in by_delta:
            value = pct_change(event_close, row_by_delta[5].get("schedule_close_price"))
            if value is not None:
                returns_5d.append(value)
        if -5 in by_delta:
            value = pct_change(row_by_delta[-5].get("schedule_close_price"), event_close)
            if value is not None:
                pre_returns_5d.append(value)

        period_moves = []
        for delta, row in row_by_delta.items():
            if -5 <= delta <= 5 and delta != 0:
                value = pct_change(event_close, row.get("schedule_close_price"))
                if value is not None:
                    period_moves.append(abs(value))
        if period_moves:
            max_abs_moves.append(max(period_moves))

    def avg(values):
        return sum(values) / len(values) if values else None

    return {
        "latest_period": latest.get("period_text") if latest else None,
        "latest_pub_trading_day": latest.get("pub_trading_day_str") if latest else None,
        "latest_pub_time": latest.get("pub_time_str") if latest else None,
        "latest_predict_vola_ratio": latest.get("predict_vola_ratio_newest") if latest else None,
        "latest_predict_vola_val": latest.get("predict_vola_val_newest") if latest else None,
        "latest_option_iv_crush": latest.get("option_iv_crush") if latest else None,
        "avg_1d_return_after_earnings": avg(returns_1d),
        "avg_5d_return_after_earnings": avg(returns_5d),
        "avg_5d_return_before_earnings": avg(pre_returns_5d),
        "avg_max_abs_move_5d": avg(max_abs_moves),
        "sample_period_count": len(by_period),
    }


def summarize_earnings_move(move_records, history_records):
    return {
        "summary": summarize_earnings_history(history_records),
        "move_rows": move_records[:120],
        "history_rows": history_records[:EARNINGS_HISTORY_MAX_ROWS],
    }


def request_earnings_move(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_earnings_move_rate_limit()
        ret_move, move_data = quote_ctx.get_financials_earnings_price_move(
            code,
            period_count=EARNINGS_MOVE_PERIOD_COUNT,
        )
        wait_for_earnings_move_rate_limit()
        ret_history, history_data = quote_ctx.get_financials_earnings_price_history(code)
    finally:
        quote_ctx.close()

    if ret_move != RET_OK:
        raise RuntimeError(f"get_financials_earnings_price_move failed for {code}: {move_data}")
    if ret_history != RET_OK:
        raise RuntimeError(f"get_financials_earnings_price_history failed for {code}: {history_data}")

    return summarize_earnings_move(
        frame_to_records(move_data),
        frame_to_records(history_data, max_rows=EARNINGS_HISTORY_MAX_ROWS),
    )


def sync_earnings_moves(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _earnings_move_lock:
        cache = load_earnings_move_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], EARNINGS_MOVE_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "earnings": request_earnings_move(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "earnings": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_earnings_move_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("earnings") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_earnings_moves(codes, force=False):
    sync_earnings_moves(codes, force=force)
    cache = load_earnings_move_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("earnings")
        for code in codes
    }


def summarize_company_profile(data):
    records = frame_to_records(data)
    fields = {}
    for row in records:
        name = str(row.get("name") or "")
        if name:
            fields[name] = row.get("value")

    return {
        "fields": fields,
        "records": records,
        "company_name": fields.get("公司名称") or fields.get("Company Name"),
        "listed_date": fields.get("上市日期") or fields.get("Listing Date"),
        "founded_date": fields.get("成立日期") or fields.get("Founded"),
        "market": fields.get("所属市场") or fields.get("Market"),
        "employee_num": fields.get("员工数量") or fields.get("Employees"),
        "website": fields.get("网址") or fields.get("Website"),
        "business": fields.get("公司业务") or fields.get("Business"),
        "description": fields.get("公司简介") or fields.get("Company Profile"),
    }


def request_company_profile(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_company_profile_rate_limit()
        ret, data = quote_ctx.get_company_profile(code)
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_company_profile failed for {code}: {data}")
    return summarize_company_profile(data)


def sync_company_profiles(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _company_profile_lock:
        cache = load_company_profile_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], COMPANY_PROFILE_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "company_profile": request_company_profile(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "company_profile": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_company_profile_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("company_profile") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_company_profiles(codes, force=False):
    sync_company_profiles(codes, force=force)
    cache = load_company_profile_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("company_profile")
        for code in codes
    }


def compact_operational_efficiency_item(item):
    return {
        "fiscal_year": json_value(item.get("fiscal_year")),
        "financial_type": json_value(item.get("financial_type")),
        "period_text": json_value(item.get("period_text")),
        "end_date": json_value(item.get("end_date")),
        "end_date_str": json_value(item.get("end_date_str")),
        "employee_num": json_value(item.get("employee_num")),
        "employee_num_yoy": json_value(item.get("employee_num_yoy")),
        "income_per_capita": json_value(item.get("income_per_capita")),
        "income_per_capita_yoy": json_value(item.get("income_per_capita_yoy")),
        "profit_per_capita": json_value(item.get("profit_per_capita")),
        "profit_per_capita_yoy": json_value(item.get("profit_per_capita_yoy")),
        "net_profit_per_capita": json_value(item.get("net_profit_per_capita")),
        "net_profit_per_capita_yoy": json_value(item.get("net_profit_per_capita_yoy")),
    }


def summarize_operational_efficiency(data):
    items = [
        compact_operational_efficiency_item(item)
        for item in (data.get("item_list", []) or [])[:OPERATIONAL_EFFICIENCY_COUNT]
    ]
    latest = items[0] if items else {}
    return {
        "currency_code": json_value(data.get("currency_code")),
        "latest": latest,
        "items": items,
        "next_key": json_value(data.get("next_key")),
    }


def request_operational_efficiency(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_operational_efficiency_rate_limit()
        ret, data = quote_ctx.get_company_operational_efficiency(
            code,
            num=OPERATIONAL_EFFICIENCY_COUNT,
        )
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_company_operational_efficiency failed for {code}: {data}")
    return summarize_operational_efficiency(data)


def sync_operational_efficiency(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _operational_efficiency_lock:
        cache = load_operational_efficiency_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], OPERATIONAL_EFFICIENCY_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "operational_efficiency": request_operational_efficiency(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "operational_efficiency": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_operational_efficiency_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("operational_efficiency") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_operational_efficiency(codes, force=False):
    sync_operational_efficiency(codes, force=force)
    cache = load_operational_efficiency_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("operational_efficiency")
        for code in codes
    }


def capital_flow_period_type():
    return getattr(PeriodType, CAPITAL_FLOW_PERIOD, PeriodType.INTRADAY)


def sum_recent(records, field, count):
    values = []
    for row in records[-count:]:
        value = row.get(field)
        if isinstance(value, (int, float)):
            values.append(float(value))
    return sum(values) if values else None


def latest_record(records):
    return records[-1] if records else {}


def summarize_capital_flow(data):
    records = frame_to_records(data, max_rows=CAPITAL_FLOW_MAX_ROWS)
    latest = latest_record(records)
    return {
        "latest": latest,
        "summary": {
            "latest_time": latest.get("capital_flow_item_time"),
            "latest_valid_time": latest.get("last_valid_time"),
            "latest_in_flow": latest.get("in_flow"),
            "latest_main_in_flow": latest.get("main_in_flow"),
            "latest_super_in_flow": latest.get("super_in_flow"),
            "latest_big_in_flow": latest.get("big_in_flow"),
            "latest_mid_in_flow": latest.get("mid_in_flow"),
            "latest_sml_in_flow": latest.get("sml_in_flow"),
            "in_flow_5": sum_recent(records, "in_flow", 5),
            "in_flow_20": sum_recent(records, "in_flow", 20),
            "main_in_flow_5": sum_recent(records, "main_in_flow", 5),
            "main_in_flow_20": sum_recent(records, "main_in_flow", 20),
            "super_in_flow_5": sum_recent(records, "super_in_flow", 5),
            "big_in_flow_5": sum_recent(records, "big_in_flow", 5),
            "sample_count": len(records),
            "period": CAPITAL_FLOW_PERIOD,
        },
        "rows": records,
    }


def request_capital_flow(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_capital_flow_rate_limit()
        ret, data = quote_ctx.get_capital_flow(
            code,
            period_type=capital_flow_period_type(),
        )
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_capital_flow failed for {code}: {data}")
    return summarize_capital_flow(data)


def sync_capital_flows(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _capital_flow_lock:
        cache = load_capital_flow_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], CAPITAL_FLOW_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "capital_flow": request_capital_flow(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "capital_flow": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_capital_flow_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("capital_flow") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_capital_flows(codes, force=False):
    sync_capital_flows(codes, force=force)
    cache = load_capital_flow_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("capital_flow")
        for code in codes
    }


def summarize_capital_distribution(data):
    records = frame_to_records(data)
    latest = latest_record(records)
    super_net = (latest.get("capital_in_super") or 0) - (latest.get("capital_out_super") or 0)
    big_net = (latest.get("capital_in_big") or 0) - (latest.get("capital_out_big") or 0)
    mid_net = (latest.get("capital_in_mid") or 0) - (latest.get("capital_out_mid") or 0)
    small_net = (latest.get("capital_in_small") or 0) - (latest.get("capital_out_small") or 0)
    return {
        "latest": latest,
        "summary": {
            "update_time": latest.get("update_time"),
            "super_net": super_net,
            "big_net": big_net,
            "main_net": super_net + big_net,
            "mid_net": mid_net,
            "small_net": small_net,
            "retail_vs_main_net": small_net - (super_net + big_net),
        },
    }


def request_capital_distribution(code):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        wait_for_capital_distribution_rate_limit()
        ret, data = quote_ctx.get_capital_distribution(code)
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_capital_distribution failed for {code}: {data}")
    return summarize_capital_distribution(data)


def sync_capital_distributions(codes, force=False):
    clean_codes = sorted({code for code in codes if code})
    with _capital_distribution_lock:
        cache = load_capital_distribution_cache()
        symbols = cache.setdefault("symbols", {})
        missing = [
            code for code in clean_codes
            if force or code not in symbols or not cache_is_fresh(symbols[code], CAPITAL_DISTRIBUTION_REFRESH_SECONDS)
        ]

        results = []
        for code in missing:
            try:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "capital_distribution": request_capital_distribution(code),
                }
                results.append({"ok": True, "code": code, "source": "moomoo"})
            except Exception as exc:
                symbols[code] = {
                    "fetched_at": utc_now_iso(),
                    "capital_distribution": None,
                    "error": str(exc),
                }
                results.append({"ok": False, "code": code, "error": str(exc)})

        save_capital_distribution_cache(cache)
        for code in clean_codes:
            if code not in missing:
                results.append({
                    "ok": symbols.get(code, {}).get("capital_distribution") is not None,
                    "code": code,
                    "source": "cache",
                    **({"error": symbols.get(code, {}).get("error")} if symbols.get(code, {}).get("error") else {}),
                })

        return {
            "ok": all(item.get("ok") for item in results),
            "count": len(results),
            "results": results,
        }


def get_capital_distributions(codes, force=False):
    sync_capital_distributions(codes, force=force)
    cache = load_capital_distribution_cache()
    symbols = cache.get("symbols", {})
    return {
        code: symbols.get(code, {}).get("capital_distribution")
        for code in codes
    }
