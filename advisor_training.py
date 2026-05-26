import json
import os
from datetime import datetime, timezone

import pandas as pd

from advisor_kline_cache import get_daily_klines
from advisor_engine import build_advisor_report, safe_float
from config import DATA_DIR


TRAINING_SAMPLES_FILE = DATA_DIR / "advisor_training_samples.json"
ADVISOR_MODEL_FILE = DATA_DIR / "advisor_model.json"
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


def financial_features(position):
    financials = position.get("profile", {}).get("financials") or {}
    return {
        "financial_latest_period": financials.get("latest_period"),
        "financial_latest_date": financials.get("latest_date"),
        "revenue": safe_float(financials.get("revenue"), None),
        "revenue_yoy": safe_float(financials.get("revenue_yoy"), None),
        "revenue_qoq": safe_float(financials.get("revenue_qoq"), None),
        "gross_profit": safe_float(financials.get("gross_profit"), None),
        "gross_profit_yoy": safe_float(financials.get("gross_profit_yoy"), None),
        "operating_profit": safe_float(financials.get("operating_profit"), None),
        "operating_profit_yoy": safe_float(financials.get("operating_profit_yoy"), None),
        "net_income": safe_float(financials.get("net_income"), None),
        "net_income_yoy": safe_float(financials.get("net_income_yoy"), None),
        "eps": safe_float(financials.get("eps"), None),
        "eps_yoy": safe_float(financials.get("eps_yoy"), None),
        "cash": safe_float(financials.get("cash"), None),
        "total_assets": safe_float(financials.get("total_assets"), None),
        "total_liabilities": safe_float(financials.get("total_liabilities"), None),
        "operating_cash_flow": safe_float(financials.get("operating_cash_flow"), None),
    }


def earnings_features(position):
    earnings = position.get("profile", {}).get("earnings") or {}
    return {
        "earnings_latest_period": earnings.get("latest_period"),
        "earnings_latest_pub_trading_day": earnings.get("latest_pub_trading_day"),
        "earnings_predict_vola_ratio": safe_float(earnings.get("latest_predict_vola_ratio"), None),
        "earnings_predict_vola_val": safe_float(earnings.get("latest_predict_vola_val"), None),
        "earnings_option_iv_crush": safe_float(earnings.get("latest_option_iv_crush"), None),
        "earnings_avg_1d_return_after": safe_float(earnings.get("avg_1d_return_after_earnings"), None),
        "earnings_avg_5d_return_after": safe_float(earnings.get("avg_5d_return_after_earnings"), None),
        "earnings_avg_5d_return_before": safe_float(earnings.get("avg_5d_return_before_earnings"), None),
        "earnings_avg_max_abs_move_5d": safe_float(earnings.get("avg_max_abs_move_5d"), None),
        "earnings_sample_period_count": safe_float(earnings.get("sample_period_count"), None),
    }


def company_profile_features(position):
    profile = position.get("profile", {}).get("company_profile") or {}
    return {
        "company_market": profile.get("market"),
        "company_listed_date": profile.get("listed_date"),
        "company_founded_date": profile.get("founded_date"),
    }


def operational_efficiency_features(position):
    efficiency = position.get("profile", {}).get("operational_efficiency") or {}
    return {
        "employee_num": safe_float(efficiency.get("employee_num"), None),
        "employee_num_yoy": safe_float(efficiency.get("employee_num_yoy"), None),
        "income_per_capita": safe_float(efficiency.get("income_per_capita"), None),
        "income_per_capita_yoy": safe_float(efficiency.get("income_per_capita_yoy"), None),
        "profit_per_capita": safe_float(efficiency.get("profit_per_capita"), None),
        "profit_per_capita_yoy": safe_float(efficiency.get("profit_per_capita_yoy"), None),
        "net_profit_per_capita": safe_float(efficiency.get("net_profit_per_capita"), None),
        "net_profit_per_capita_yoy": safe_float(efficiency.get("net_profit_per_capita_yoy"), None),
    }


def capital_features(position):
    capital_flow = position.get("profile", {}).get("capital_flow") or {}
    capital_distribution = position.get("profile", {}).get("capital_distribution") or {}
    return {
        "capital_latest_in_flow": safe_float(capital_flow.get("latest_in_flow"), None),
        "capital_latest_main_in_flow": safe_float(capital_flow.get("latest_main_in_flow"), None),
        "capital_in_flow_5": safe_float(capital_flow.get("in_flow_5"), None),
        "capital_in_flow_20": safe_float(capital_flow.get("in_flow_20"), None),
        "capital_main_in_flow_5": safe_float(capital_flow.get("main_in_flow_5"), None),
        "capital_main_in_flow_20": safe_float(capital_flow.get("main_in_flow_20"), None),
        "capital_super_in_flow_5": safe_float(capital_flow.get("super_in_flow_5"), None),
        "capital_big_in_flow_5": safe_float(capital_flow.get("big_in_flow_5"), None),
        "capital_distribution_main_net": safe_float(capital_distribution.get("main_net"), None),
        "capital_distribution_super_net": safe_float(capital_distribution.get("super_net"), None),
        "capital_distribution_big_net": safe_float(capital_distribution.get("big_net"), None),
        "capital_distribution_small_net": safe_float(capital_distribution.get("small_net"), None),
        "capital_distribution_retail_vs_main_net": safe_float(capital_distribution.get("retail_vs_main_net"), None),
    }


def short_features(position):
    daily_short_volume = position.get("profile", {}).get("daily_short_volume") or {}
    short_interest = position.get("profile", {}).get("short_interest") or {}
    return {
        "short_volume_latest_short_percent": safe_float(daily_short_volume.get("latest_short_percent"), None),
        "short_volume_avg_short_percent_5": safe_float(daily_short_volume.get("avg_short_percent_5"), None),
        "short_volume_avg_short_percent_20": safe_float(daily_short_volume.get("avg_short_percent_20"), None),
        "short_volume_avg_daily_trade_ratio_20": safe_float(daily_short_volume.get("avg_daily_trade_ratio_20"), None),
        "short_interest_shares_short": safe_float(short_interest.get("shares_short"), None),
        "short_interest_short_percent": safe_float(short_interest.get("short_percent"), None),
        "short_interest_days_to_cover": safe_float(short_interest.get("days_to_cover"), None),
        "short_interest_change_vs_previous": safe_float(short_interest.get("short_change_vs_previous"), None),
    }


def shareholders_features(position):
    overview = position.get("profile", {}).get("shareholders_overview") or {}
    changes = position.get("profile", {}).get("shareholders_changes") or {}
    return {
        "shareholders_top_holder_pct": safe_float(overview.get("top_holder_pct"), None),
        "shareholders_top5_holder_pct": safe_float(overview.get("top5_holder_pct"), None),
        "shareholders_top10_holder_pct": safe_float(overview.get("top10_holder_pct"), None),
        "shareholders_change_count": safe_float(changes.get("change_count"), None),
        "shareholders_positive_change_count": safe_float(changes.get("positive_change_count"), None),
        "shareholders_negative_change_count": safe_float(changes.get("negative_change_count"), None),
        "shareholders_net_share_ratio_change": safe_float(changes.get("net_share_ratio_change"), None),
        "shareholders_largest_buy_share_ratio_change": safe_float(changes.get("largest_buy_share_ratio_change"), None),
        "shareholders_largest_sell_share_ratio_change": safe_float(changes.get("largest_sell_share_ratio_change"), None),
    }


def insider_features(position):
    trades = position.get("profile", {}).get("insider_trades") or {}
    holders = position.get("profile", {}).get("insider_holders") or {}
    return {
        "insider_trade_count": safe_float(trades.get("trade_count"), None),
        "insider_buy_count": safe_float(trades.get("buy_count"), None),
        "insider_sell_count": safe_float(trades.get("sell_count"), None),
        "insider_proposed_sale_count": safe_float(trades.get("proposed_sale_count"), None),
        "insider_net_trade_shares": safe_float(trades.get("net_trade_shares"), None),
        "insider_total_count": safe_float(holders.get("insider_total_count"), None),
        "insider_bought_count": safe_float(holders.get("insider_bought_count"), None),
        "insider_sold_count": safe_float(holders.get("insider_sold_count"), None),
        "insider_top_holder_pct": safe_float(holders.get("top_holder_pct"), None),
        "insider_top5_holder_pct": safe_float(holders.get("top5_holder_pct"), None),
    }


def price_structure_features(position):
    structure = position.get("price_structure") or {}
    return {
        "price_structure_score": safe_float(structure.get("score"), None),
        "price_structure_recent_high_20": safe_float(structure.get("recent_high_20"), None),
        "price_structure_recent_low_20": safe_float(structure.get("recent_low_20"), None),
        "price_structure_range_20": safe_float(structure.get("range_20"), None),
        "price_structure_range_60": safe_float(structure.get("range_60"), None),
        "price_structure_volume_expansion": bool(structure.get("volume_expansion")),
        "price_structure_swing_low_count": len(structure.get("swing_lows") or []),
        "price_structure_swing_high_count": len(structure.get("swing_highs") or []),
    }


def personality_features(position):
    personality = position.get("profile", {}).get("personality") or {}
    return {
        "personality_speculative": bool(personality.get("speculative")),
        "personality_short_squeeze_sensitive": bool(personality.get("short_squeeze_sensitive")),
        "personality_rsi_hot_threshold": safe_float(personality.get("rsi_hot_threshold"), None),
        "personality_max_buy_percent": safe_float(personality.get("max_buy_percent"), None),
        "personality_trim_bias": safe_float(personality.get("trim_bias"), None),
    }


def score_breakdown_features(position):
    breakdown = position.get("score_breakdown") or {}
    return {
        f"score_{key}": safe_float(value, None)
        for key, value in breakdown.items()
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
        "data_quality_ok": bool(position.get("data_quality", {}).get("ok")),
        "price_scale_ok": bool(position.get("data_quality", {}).get("price_scale_ok")),
        "price_scale_ratio": safe_float(position.get("data_quality", {}).get("price_scale_ratio"), None),
        "position_price": safe_float(position.get("data_quality", {}).get("position_price"), None),
        "technical_score": safe_float(position.get("technical_score")),
        "risk_score": safe_float(position.get("risk_score")),
        "ma5": safe_float(daily.get("ma5")),
        "ma20": safe_float(daily.get("ma20")),
        "ma60": safe_float(daily.get("ma60")),
        "rsi14": safe_float(daily.get("rsi14")),
        "macd": safe_float(daily.get("macd")),
        "macd_signal": safe_float(daily.get("macd_signal")),
        "macd_hist": safe_float(daily.get("macd_hist")),
        "atr14": safe_float(daily.get("atr14")),
        "boll_mid": safe_float(daily.get("boll_mid")),
        "boll_upper": safe_float(daily.get("boll_upper")),
        "boll_lower": safe_float(daily.get("boll_lower")),
        "volatility_60d": safe_float(daily.get("volatility_60d")),
        "weekly_boll_position": safe_float(weekly.get("boll_position")),
        "monthly_ma20": safe_float(monthly.get("ma20")),
        "trend_5d": safe_float(position.get("prediction", {}).get("trend_5d")),
        "trend_20d": safe_float(position.get("prediction", {}).get("trend_20d")),
        "trend_60d": safe_float(position.get("prediction", {}).get("trend_60d")),
        "expected_volatility_30d": safe_float(position.get("prediction", {}).get("expected_volatility_30d")),
        "drawdown_from_high": safe_float(position.get("prediction", {}).get("drawdown_from_high")),
        **price_structure_features(position),
        **personality_features(position),
        **score_breakdown_features(position),
        **valuation_features(position),
        **financial_features(position),
        **earnings_features(position),
        **company_profile_features(position),
        **operational_efficiency_features(position),
        **capital_features(position),
        **short_features(position),
        **shareholders_features(position),
        **insider_features(position),
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

    price_structure = position.get("price_structure") or {}
    if price_structure:
        signals.append({
            "name": "price_structure_status",
            "value": price_structure.get("status"),
            "direction": price_structure.get("status"),
            "confidence": None,
            "source": "price_action",
            "reason": "裸K结构状态",
        })
        for point in price_structure.get("points", []) or []:
            signals.append({
                "name": "price_structure_point",
                "value": point,
                "direction": "informational",
                "confidence": None,
                "source": "price_action",
                "reason": point,
            })

    personality = position.get("profile", {}).get("personality") or {}
    if personality:
        signals.append({
            "name": "personality_type",
            "value": personality.get("type"),
            "direction": personality.get("type"),
            "confidence": None,
            "source": "advisor_profile",
            "reason": personality.get("strategy_note"),
        })

    for point in position.get("analysis_points", []) or []:
        signals.append({
            "name": f"analysis_{point.get('category', 'unknown')}_{point.get('label', 'point')}",
            "value": point.get("status"),
            "direction": point.get("status"),
            "confidence": None,
            "source": point.get("category"),
            "reason": point.get("detail"),
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
            "personality_type": position.get("profile", {}).get("personality", {}).get("type"),
            "price_structure_status": position.get("price_structure", {}).get("status"),
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
        if not position.get("data_quality", {}).get("ok", True):
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


def pearson(xs, ys):
    pairs = [
        (float(x), float(y))
        for x, y in zip(xs, ys)
        if x is not None and y is not None
    ]
    if len(pairs) < 3:
        return None
    x_values = [item[0] for item in pairs]
    y_values = [item[1] for item in pairs]
    x_mean = sum(x_values) / len(x_values)
    y_mean = sum(y_values) / len(y_values)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in pairs)
    x_var = sum((x - x_mean) ** 2 for x in x_values)
    y_var = sum((y - y_mean) ** 2 for y in y_values)
    if x_var <= 0 or y_var <= 0:
        return None
    return numerator / ((x_var ** 0.5) * (y_var ** 0.5))


def train_advisor_model(horizon=20, min_samples=8):
    payload = load_training_samples()
    rows = []
    for sample in payload.get("samples", []):
        features = sample.get("features", {})
        if features.get("data_quality_ok") is False:
            continue
        target = (sample.get("targets", {}) or {}).get(str(horizon))
        if not target:
            continue
        actual_return = safe_float(target.get("actual_return"), None)
        max_drawdown = safe_float(target.get("actual_max_drawdown"), None)
        if actual_return is None:
            continue
        rows.append({
            "sample": sample,
            "features": features,
            "actual_return": actual_return,
            "max_drawdown": max_drawdown,
        })

    numeric_keys = sorted({
        key
        for row in rows
        for key, value in row["features"].items()
        if isinstance(value, (int, float)) and value is not None and not isinstance(value, bool)
    })
    factors = []
    for key in numeric_keys:
        xs = [row["features"].get(key) for row in rows]
        returns = [row["actual_return"] for row in rows]
        drawdowns = [row["max_drawdown"] for row in rows]
        return_corr = pearson(xs, returns)
        drawdown_corr = pearson(xs, drawdowns)
        if return_corr is None and drawdown_corr is None:
            continue
        factors.append({
            "feature": key,
            "return_corr": None if return_corr is None else round(return_corr, 6),
            "drawdown_corr": None if drawdown_corr is None else round(drawdown_corr, 6),
            "importance": round(max(abs(return_corr or 0), abs(drawdown_corr or 0)), 6),
        })

    factors.sort(key=lambda item: item["importance"], reverse=True)
    model = {
        "ok": len(rows) >= min_samples,
        "updated_at": utc_now_iso(),
        "schema_version": 1,
        "type": "factor_correlation_v1",
        "horizon": horizon,
        "min_samples": min_samples,
        "sample_count": len(rows),
        "usable": len(rows) >= min_samples,
        "note": "This first model ranks which recorded features have historically aligned with future returns/drawdowns. It is intentionally not used for trading until enough clean samples exist.",
        "top_factors": factors[:30],
    }
    write_json(ADVISOR_MODEL_FILE, model)
    return model


def get_advisor_model():
    return read_json(ADVISOR_MODEL_FILE, {
        "ok": False,
        "error": "advisor model has not been trained yet",
    })
