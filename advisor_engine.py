import json
import math
import os
from datetime import datetime, timezone

import pandas as pd

from advisor_kline_cache import (
    get_daily_klines,
    get_period_klines,
    sync_all_period_klines,
    sync_daily_klines,
)
from config import DATA_DIR
from routes.positions import get_positions


ADVISOR_STATE_FILE = DATA_DIR / "advisor_state.json"
ADVISOR_REPORT_FILE = DATA_DIR / "advisor_report.json"
SYMBOL_META_FILE = DATA_DIR / "advisor_symbol_meta.json"

DEFAULT_WEIGHTS = {
    "trend": 0.28,
    "momentum": 0.20,
    "volatility": 0.20,
    "drawdown": 0.17,
    "position_weight": 0.15,
}

DEFAULT_SYMBOL_META = {
    "US.SIDU": {
        "sector": "Space / Aerospace",
        "theme": ["SpaceX sentiment", "small cap", "high volatility"],
        "risk_tier": "speculative",
    }
}


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


def load_advisor_state():
    state = read_json(ADVISOR_STATE_FILE, {})
    if not state:
        state = {
            "updated_at": utc_now_iso(),
            "version": 1,
            "weights": DEFAULT_WEIGHTS,
            "prediction_horizons": [5, 20, 60],
            "notes": "Rule-based advisor v1. Future versions can adjust weights from prediction validation.",
        }
        write_json(ADVISOR_STATE_FILE, state)
    state.setdefault("weights", DEFAULT_WEIGHTS)
    return state


def load_symbol_meta():
    meta = read_json(SYMBOL_META_FILE, DEFAULT_SYMBOL_META)
    if not SYMBOL_META_FILE.exists():
        write_json(SYMBOL_META_FILE, meta)
    return meta


def safe_float(value, default=0.0):
    try:
        result = float(value)
        if math.isnan(result) or math.isinf(result):
            return default
        return result
    except Exception:
        return default


def add_indicators(frame):
    if frame.empty:
        return frame
    data = frame.copy().sort_values("date")
    close = data["close"]
    high = data["high"]
    low = data["low"]
    data["ma20"] = close.rolling(20).mean()
    data["ma60"] = close.rolling(60).mean()
    data["ma120"] = close.rolling(120).mean()
    data["ret_1d"] = close.pct_change()
    data["ret_20d"] = close.pct_change(20)
    data["ret_60d"] = close.pct_change(60)
    data["volatility_20d"] = data["ret_1d"].rolling(20).std() * math.sqrt(252)
    data["volatility_60d"] = data["ret_1d"].rolling(60).std() * math.sqrt(252)

    delta = close.diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    rs = gain / loss.replace(0, pd.NA)
    data["rsi14"] = 100 - (100 / (1 + rs))

    ema12 = close.ewm(span=12, adjust=False).mean()
    ema26 = close.ewm(span=26, adjust=False).mean()
    data["macd"] = ema12 - ema26
    data["macd_signal"] = data["macd"].ewm(span=9, adjust=False).mean()

    mid = close.rolling(20).mean()
    std = close.rolling(20).std()
    data["boll_mid"] = mid
    data["boll_upper"] = mid + 2 * std
    data["boll_lower"] = mid - 2 * std
    data["boll_position"] = (close - data["boll_lower"]) / (data["boll_upper"] - data["boll_lower"])

    prev_close = close.shift(1)
    true_range = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    data["atr14"] = true_range.rolling(14).mean()
    data["drawdown"] = close / close.cummax() - 1
    return data


def aggregate_period(frame, freq):
    if frame.empty:
        return frame
    data = frame.copy()
    data["date"] = pd.to_datetime(data["date"])
    data = data.set_index("date")
    result = data.resample(freq).agg({
        "open": "first",
        "high": "max",
        "low": "min",
        "close": "last",
        "volume": "sum",
        "turnover": "sum",
    }).dropna(subset=["close"])
    result["date"] = result.index.date.astype(str)
    return result.reset_index(drop=True)


def score_position(position, daily_frame, portfolio_value, weights, meta):
    code = position.get("code", "")
    market_val = safe_float(position.get("market_val"))
    weight = market_val / portfolio_value if portfolio_value > 0 else 0
    indicators = add_indicators(daily_frame)
    weekly_source = get_period_klines(code, period="week")
    monthly_source = get_period_klines(code, period="month")
    weekly = add_indicators(weekly_source if not weekly_source.empty else aggregate_period(daily_frame, "W-FRI"))
    monthly = add_indicators(monthly_source if not monthly_source.empty else aggregate_period(daily_frame, "ME"))

    if indicators.empty:
        return {
            "code": code,
            "name": position.get("name", ""),
            "risk_score": 50,
            "technical_score": 50,
            "action": "watch",
            "suggestion": "K线缓存不足，先观察并等待日线数据同步完成。",
            "reasons": ["缺少历史日K数据"],
        }

    latest = indicators.iloc[-1]
    latest_week = weekly.iloc[-1] if not weekly.empty else latest
    latest_month = monthly.iloc[-1] if not monthly.empty else latest
    close = safe_float(latest.get("close"))
    ma20 = safe_float(latest.get("ma20"))
    ma60 = safe_float(latest.get("ma60"))
    rsi = safe_float(latest.get("rsi14"), 50)
    vol60 = safe_float(latest.get("volatility_60d"))
    drawdown = abs(safe_float(latest.get("drawdown")))
    ret20 = safe_float(latest.get("ret_20d"))
    ret60 = safe_float(latest.get("ret_60d"))
    boll_position = safe_float(latest_week.get("boll_position"), 0.5)

    trend_score = 50
    reasons = []
    if close > ma20 > 0:
        trend_score += 10
        reasons.append("日线价格站上20日均线")
    if ma20 > ma60 > 0:
        trend_score += 12
        reasons.append("20日均线高于60日均线")
    if close < ma60 and ma60 > 0:
        trend_score -= 15
        reasons.append("价格仍低于60日均线")

    momentum_score = 50 + max(-25, min(25, ret20 * 100)) + max(-15, min(15, ret60 * 50))
    if 45 <= rsi <= 68:
        momentum_score += 8
        reasons.append("RSI处在相对健康区间")
    elif rsi > 75:
        momentum_score -= 10
        reasons.append("RSI偏热，追高风险上升")
    elif rsi < 35:
        momentum_score -= 8
        reasons.append("RSI偏弱，趋势仍需确认")

    volatility_risk = min(100, vol60 * 100)
    drawdown_risk = min(100, drawdown * 160)
    concentration_risk = min(100, weight * 250)
    risk_tier = meta.get(code, {}).get("risk_tier", "")
    speculative_addon = 15 if risk_tier == "speculative" else 0
    risk_score = (
        volatility_risk * weights["volatility"]
        + drawdown_risk * weights["drawdown"]
        + concentration_risk * weights["position_weight"]
        + speculative_addon
        + max(0, 50 - trend_score) * weights["trend"]
    )
    risk_score = round(max(0, min(100, risk_score)), 1)

    technical_score = (
        trend_score * weights["trend"]
        + momentum_score * weights["momentum"]
        + (100 - volatility_risk) * weights["volatility"]
        + (100 - drawdown_risk) * weights["drawdown"]
        + (100 - concentration_risk) * weights["position_weight"]
    )
    technical_score = round(max(0, min(100, technical_score)), 1)

    if boll_position > 0.55:
        reasons.append("周线布林带位置偏强，仍在中轨上方或附近")
    elif boll_position < 0.35:
        reasons.append("周线布林带偏弱，反弹确认度不足")

    action = "hold"
    suggestion = "继续观察，等待趋势和风险信号进一步确认。"
    if risk_score >= 70 and weight >= 0.15:
        action = "trim"
        suggestion = "风险和仓位都偏高，可考虑分批减仓10%-30%，优先降低组合波动。"
    elif technical_score >= 68 and risk_score < 55 and weight < 0.20:
        action = "add_candidate"
        suggestion = "技术面较强且组合占比未过高，可列入加仓观察，不建议一次性重仓。"
    elif technical_score >= 58 and risk_score < 70:
        action = "hold"
        suggestion = "趋势尚可，当前以持有/观望为主。"
    elif technical_score < 45:
        action = "reduce_or_watch"
        suggestion = "技术面偏弱，若反弹无量或跌破关键均线，应考虑降低仓位。"

    if safe_float(position.get("unrealized_pl")) > 0 and risk_score >= 60:
        reasons.append("已有浮盈且风险分偏高，适合预设分批止盈计划")

    return {
        "code": code,
        "name": position.get("name", ""),
        "sector": meta.get(code, {}).get("sector", "Unknown"),
        "theme": meta.get(code, {}).get("theme", []),
        "weight": round(weight, 4),
        "market_val": market_val,
        "close": close,
        "risk_score": risk_score,
        "technical_score": technical_score,
        "action": action,
        "suggestion": suggestion,
        "prediction": {
            "expected_volatility_30d": round(vol60 / math.sqrt(252) * math.sqrt(30), 4) if vol60 else 0,
            "trend_20d": round(ret20, 4),
            "trend_60d": round(ret60, 4),
            "drawdown_from_high": round(drawdown, 4),
        },
        "signals": {
            "daily": {
                "ma20": round(ma20, 4),
                "ma60": round(ma60, 4),
                "rsi14": round(rsi, 2),
                "volatility_60d": round(vol60, 4),
            },
            "weekly": {
                "boll_position": round(safe_float(latest_week.get("boll_position"), 0.5), 4),
                "close": round(safe_float(latest_week.get("close")), 4),
            },
            "monthly": {
                "close": round(safe_float(latest_month.get("close")), 4),
                "ma20": round(safe_float(latest_month.get("ma20")), 4),
            },
        },
        "reasons": reasons[:8],
    }


def portfolio_exposure(position_reports):
    total = sum(item.get("market_val", 0) for item in position_reports)
    by_sector = {}
    for item in position_reports:
        sector = item.get("sector", "Unknown")
        by_sector[sector] = by_sector.get(sector, 0) + item.get("market_val", 0)
    return {
        sector: round(value / total, 4) if total > 0 else 0
        for sector, value in sorted(by_sector.items(), key=lambda pair: pair[1], reverse=True)
    }


def correlation_summary(codes):
    returns = {}
    for code in codes:
        frame = get_daily_klines(code)
        if frame.empty:
            continue
        data = frame.tail(180).copy()
        returns[code] = data["close"].pct_change().reset_index(drop=True)
    if len(returns) < 2:
        return {"pairs": []}
    table = pd.DataFrame(returns).dropna(how="all")
    corr = table.corr()
    pairs = []
    for i, left in enumerate(corr.columns):
        for right in corr.columns[i + 1:]:
            value = corr.loc[left, right]
            if pd.isna(value):
                continue
            if abs(value) >= 0.65:
                pairs.append({
                    "left": left,
                    "right": right,
                    "correlation": round(float(value), 4),
                })
    pairs.sort(key=lambda item: abs(item["correlation"]), reverse=True)
    return {"pairs": pairs[:10]}


def sync_advisor_klines(force=False):
    positions_result = get_positions()
    if not positions_result.get("ok"):
        return positions_result
    codes = [item["code"] for item in positions_result.get("positions", []) if item.get("code")]
    results = []
    for code in codes:
        try:
            results.extend(sync_all_period_klines(code, force=force))
        except Exception as exc:
            results.append({"ok": False, "code": code, "error": str(exc)})
    return {
        "ok": all(item.get("ok") for item in results),
        "count": len(results),
        "results": results,
    }


def build_advisor_report(force_sync=False):
    state = load_advisor_state()
    meta = load_symbol_meta()
    positions_result = get_positions()
    if not positions_result.get("ok"):
        return positions_result

    positions = positions_result.get("positions", [])
    if force_sync:
        for position in positions:
            code = position.get("code")
            if code:
                sync_all_period_klines(code, force=True)

    portfolio_value = sum(safe_float(item.get("market_val")) for item in positions)
    reports = []
    for position in positions:
        code = position.get("code")
        if not code:
            continue
        frame = get_daily_klines(code)
        reports.append(score_position(position, frame, portfolio_value, state["weights"], meta))

    exposure = portfolio_exposure(reports)
    max_position = max([item.get("weight", 0) for item in reports], default=0)
    high_risk_weight = sum(item.get("weight", 0) for item in reports if item.get("risk_score", 0) >= 70)
    portfolio_risk = min(100, max_position * 120 + high_risk_weight * 60)
    portfolio_reasons = []
    if max_position >= 0.30:
        portfolio_reasons.append("单一持仓占比超过30%，组合集中度偏高")
    if high_risk_weight >= 0.35:
        portfolio_reasons.append("高风险持仓合计占比较高，回撤压力上升")
    for sector, weight in exposure.items():
        if weight >= 0.45:
            portfolio_reasons.append(f"{sector} 暴露达到 {weight:.0%}，板块集中度偏高")

    report = {
        "ok": True,
        "updated_at": utc_now_iso(),
        "model": {
            "type": "rule_based_advisor_v1",
            "weights": state["weights"],
            "training_mode": "prediction_logging_ready",
        },
        "portfolio": {
            "market_value": round(portfolio_value, 2),
            "risk_score": round(portfolio_risk, 1),
            "max_position_weight": round(max_position, 4),
            "high_risk_weight": round(high_risk_weight, 4),
            "sector_exposure": exposure,
            "correlation": correlation_summary([item.get("code") for item in reports]),
            "reasons": portfolio_reasons,
        },
        "positions": sorted(reports, key=lambda item: item.get("risk_score", 0), reverse=True),
    }
    write_json(ADVISOR_REPORT_FILE, report)
    return report


def load_latest_report():
    return read_json(ADVISOR_REPORT_FILE, {"ok": False, "error": "advisor report not generated yet"})


def get_symbol_advice(code, refresh=False):
    report = build_advisor_report(force_sync=False) if refresh else load_latest_report()
    if not report.get("ok"):
        report = build_advisor_report(force_sync=False)
    for position in report.get("positions", []):
        if position.get("code") == code:
            return {
                "ok": True,
                "updated_at": report.get("updated_at"),
                "position": position,
            }
    return {
        "ok": False,
        "error": f"{code} is not in current positions",
    }
