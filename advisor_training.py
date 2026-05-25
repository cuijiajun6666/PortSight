import json
import os
from datetime import datetime, timezone

import pandas as pd

from advisor_kline_cache import get_daily_klines
from advisor_engine import build_advisor_report, safe_float
from config import DATA_DIR


TRAINING_SAMPLES_FILE = DATA_DIR / "advisor_training_samples.json"
DEFAULT_HORIZONS = [5, 20, 60]


def utc_now_iso():
    return datetime.now(timezone.utc).isoformat()


def read_json(path, default):
    try:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)
    except FileNotFoundError:
        return default
    except json.JSONDecodeError:
        return default


def write_json(path, payload):
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")
    os.replace(tmp_path, path)


def load_training_samples():
    return read_json(TRAINING_SAMPLES_FILE, {
        "updated_at": None,
        "schema_version": 1,
        "samples": [],
    })


def save_training_samples(payload):
    payload["updated_at"] = utc_now_iso()
    payload.setdefault("schema_version", 1)
    payload.setdefault("samples", [])
    write_json(TRAINING_SAMPLES_FILE, payload)


def sample_id(trading_date, symbol):
    return f"{trading_date}|{symbol}"


def latest_kline_date(symbol):
    frame = get_daily_klines(symbol)
    if frame.empty:
        return None
    return str(frame.iloc[-1]["date"])


def valuation_features(position):
    valuation = position.get("profile", {}).get("valuation") or {}
    trend = valuation.get("trend", {})
    market = valuation.get("market_distribution", {})
    plate = valuation.get("plate_distribution", {})
    growth = valuation.get("profit_growth_rate", {})
    return {
        "valuation_type": valuation.get("valuation_type"),
        "valuation_current": safe_float(trend.get("current_value"), None),
        "valuation_average": safe_float(trend.get("average_value"), None),
        "valuation_percentile": safe_float(trend.get("valuation_percentile"), None),
        "valuation_forward": safe_float(trend.get("forward_value"), None),
        "market_valuation_ranking": safe_float(market.get("ranking"), None),
        "market_valuation_average": safe_float(market.get("average_value"), None),
        "market_valuation_median": safe_float(market.get("median_value"), None),
        "plate_valuation_ranking": safe_float(plate.get("plate_ranking"), None),
        "plate_stock_item_count": safe_float(plate.get("plate_stock_item_count"), None),
        "plate_average_value": safe_float(plate.get("plate_average_value"), None),
        "financial_ttm_multiple": safe_float(growth.get("financial_ttm_multiple"), None),
        "market_cap_multiple": safe_float(growth.get("market_cap_multiple"), None),
        "growth_year_count": safe_float(growth.get("year_count"), None),
    }


def build_feature_row(report, position):
    daily = position.get("signals", {}).get("daily", {})
    weekly = position.get("signals", {}).get("weekly", {})
    monthly = position.get("signals", {}).get("monthly", {})
    portfolio = report.get("portfolio", {})
    sector = position.get("sector", "Unknown")
    sector_exposure = portfolio.get("sector_exposure", {}).get(sector, 0)

    features = {
        "portfolio_risk_score": safe_float(portfolio.get("risk_score")),
        "portfolio_max_position_weight": safe_float(portfolio.get("max_position_weight")),
        "portfolio_high_risk_weight": safe_float(portfolio.get("high_risk_weight")),
        "sector_exposure": safe_float(sector_exposure),
        "position_weight": safe_float(position.get("weight")),
        "market_val": safe_float(position.get("market_val")),
        "close": safe_float(position.get("close")),
        "technical_score": safe_float(position.get("technical_score")),
        "risk_score": safe_float(position.get("risk_score")),
        "ma20": safe_float(daily.get("ma20")),
        "ma60": safe_float(daily.get("ma60")),
        "rsi14": safe_float(daily.get("rsi14")),
        "volatility_60d": safe_float(daily.get("volatility_60d")),
        "weekly_boll_position": safe_float(weekly.get("boll_position")),
        "monthly_ma20": safe_float(monthly.get("ma20")),
        "trend_20d": safe_float(position.get("prediction", {}).get("trend_20d")),
        "trend_60d": safe_float(position.get("prediction", {}).get("trend_60d")),
        "expected_volatility_30d": safe_float(position.get("prediction", {}).get("expected_volatility_30d")),
        "drawdown_from_high": safe_float(position.get("prediction", {}).get("drawdown_from_high")),
        **valuation_features(position),
    }

    signals = [
        {
            "name": "advisor_action",
            "value": position.get("action"),
            "direction": position.get("action"),
            "confidence": None,
            "source": "advisor_engine",
            "reason": position.get("suggestion"),
        },
        {
            "name": "volatility_tier",
            "value": position.get("profile", {}).get("volatility_tier"),
            "direction": "bearish" if position.get("profile", {}).get("volatility_tier") in ("high", "extreme") else "neutral",
            "confidence": 0.7,
            "source": "historical_kline",
            "reason": "由历史日K计算60日年化波动率得到",
        },
    ]

    for reason in position.get("reasons", []):
        signals.append({
            "name": "advisor_reason",
            "value": reason,
            "direction": "informational",
            "confidence": None,
            "source": "advisor_engine",
            "reason": reason,
        })

    return features, signals


def make_sample(report, position, horizons=None):
    symbol = position.get("code")
    trading_date = latest_kline_date(symbol) or str(report.get("updated_at", ""))[:10]
    horizons = horizons or DEFAULT_HORIZONS
    features, signals = build_feature_row(report, position)
    return {
        "id": sample_id(trading_date, symbol),
        "created_at": utc_now_iso(),
        "trading_date": trading_date,
        "symbol": symbol,
        "name": position.get("name"),
        "sector": position.get("sector"),
        "features": features,
        "categorical_features": {
            "action": position.get("action"),
            "risk_tier": position.get("profile", {}).get("risk_tier"),
            "size_tier": position.get("profile", {}).get("size_tier"),
            "volatility_tier": position.get("profile", {}).get("volatility_tier"),
        },
        "signals": signals,
        "prediction": {
            "action": position.get("action"),
            "suggestion": position.get("suggestion"),
            "risk_score": position.get("risk_score"),
            "technical_score": position.get("technical_score"),
            "horizons": horizons,
        },
        "targets": {
            str(horizon): None
            for horizon in horizons
        },
    }


def record_training_samples(report=None, horizons=None):
    report = report or build_advisor_report()
    if not report.get("ok"):
        return report

    payload = load_training_samples()
    samples_by_id = {
        sample.get("id"): sample
        for sample in payload.get("samples", [])
        if sample.get("id")
    }

    created = 0
    updated = 0
    for position in report.get("positions", []):
        symbol = position.get("code")
        if not symbol:
            continue
        sample = make_sample(report, position, horizons=horizons)
        existing = samples_by_id.get(sample["id"])
        if existing:
            sample["created_at"] = existing.get("created_at", sample["created_at"])
            sample["targets"] = existing.get("targets", sample["targets"])
            updated += 1
        else:
            created += 1
        samples_by_id[sample["id"]] = sample

    payload["samples"] = sorted(
        samples_by_id.values(),
        key=lambda item: (item.get("trading_date", ""), item.get("symbol", "")),
    )
    save_training_samples(payload)
    return {
        "ok": True,
        "created": created,
        "updated": updated,
        "count": len(payload["samples"]),
    }


def future_window(frame, trading_date, horizon):
    data = frame.copy().sort_values("date")
    data["date"] = pd.to_datetime(data["date"]).dt.date.astype(str)
    future = data[data["date"] > trading_date].head(horizon)
    if len(future) < horizon:
        return None
    return future


def build_target(entry_close, future):
    final = future.iloc[-1]
    close_series = future["close"].astype(float)
    return {
        "resolved_at": utc_now_iso(),
        "target_date": str(final["date"]),
        "actual_return": round(float(final["close"]) / entry_close - 1, 6) if entry_close else None,
        "actual_max_drawdown": round(float(close_series.min()) / entry_close - 1, 6) if entry_close else None,
        "actual_max_runup": round(float(close_series.max()) / entry_close - 1, 6) if entry_close else None,
        "final_close": safe_float(final["close"]),
    }


def update_training_targets():
    payload = load_training_samples()
    resolved = 0
    pending = 0

    for sample in payload.get("samples", []):
        symbol = sample.get("symbol")
        trading_date = sample.get("trading_date")
        entry_close = safe_float(sample.get("features", {}).get("close"))
        if not symbol or not trading_date or not entry_close:
            continue

        frame = get_daily_klines(symbol)
        if frame.empty:
            continue

        targets = sample.setdefault("targets", {})
        for horizon_key, target in list(targets.items()):
            if target is not None:
                continue
            horizon = int(horizon_key)
            future = future_window(frame, trading_date, horizon)
            if future is None:
                pending += 1
                continue
            targets[horizon_key] = build_target(entry_close, future)
            resolved += 1

    save_training_samples(payload)
    return {
        "ok": True,
        "resolved": resolved,
        "pending": pending,
        "count": len(payload.get("samples", [])),
    }


def get_training_samples(limit=200, symbol=None):
    payload = load_training_samples()
    samples = payload.get("samples", [])
    if symbol:
        samples = [sample for sample in samples if sample.get("symbol") == symbol]
    samples = samples[-limit:] if limit else samples
    return {
        "ok": True,
        "updated_at": payload.get("updated_at"),
        "count": len(samples),
        "samples": samples,
    }

