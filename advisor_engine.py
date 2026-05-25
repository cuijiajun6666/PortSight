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
from advisor_profile import (
    get_financials,
    get_owner_plates,
    get_valuations,
    sync_financials,
    sync_owner_plates,
    sync_valuations,
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
        "theme": ["SpaceX sentiment", "small cap", "high volatility"],
        "risk_tier": "speculative",
        "size_tier": "small_cap",
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


def plate_names(plates):
    return [
        str(plate.get("plate_name", ""))
        for plate in plates
        if plate.get("plate_name")
    ]


def classify_sector(code, meta, plates):
    if meta.get(code, {}).get("sector"):
        return meta[code]["sector"]

    names = plate_names(plates)
    keywords = [
        ("Semiconductor", ["semiconductor", "chip", "芯片", "半导体"]),
        ("Technology", ["technology", "software", "internet", "科技", "软件", "互联网"]),
        ("Space / Aerospace", ["space", "aerospace", "satellite", "航天", "航空", "卫星"]),
        ("Biotech / Healthcare", ["biotech", "health", "medical", "pharma", "生物", "医疗", "医药"]),
        ("Energy", ["energy", "oil", "gas", "solar", "新能源", "能源", "石油"]),
        ("Financials", ["bank", "financial", "insurance", "银行", "金融", "保险"]),
        ("Consumer", ["consumer", "retail", "消费", "零售"]),
        ("Crypto / Digital Assets", ["crypto", "bitcoin", "blockchain", "加密", "区块链"]),
    ]
    lower_names = [name.lower() for name in names]
    for sector, words in keywords:
        if any(word.lower() in name for name in lower_names for word in words):
            return sector

    for name in names:
        lower_name = name.lower()
        if not any(skip in lower_name for skip in ["constituent", "index", "adr", "etf", "成份", "指数"]):
            return name
    return "Unknown"


def infer_size_tier(code, meta, plates):
    configured = meta.get(code, {}).get("size_tier")
    if configured:
        return configured
    names = " ".join(plate_names(plates)).lower()
    if any(word in names for word in ["micro", "small cap", "small-cap", "小盘"]):
        return "small_cap"
    if any(word in names for word in ["mega", "large cap", "large-cap", "大盘"]):
        return "large_cap"
    return "unknown"


def volatility_tier(volatility):
    if volatility >= 1.0:
        return "extreme"
    if volatility >= 0.65:
        return "high"
    if volatility >= 0.35:
        return "medium"
    return "low"


def valuation_percentile_to_unit(value):
    percentile = safe_float(value, -1)
    if percentile < 0:
        return None
    if percentile > 1:
        percentile = percentile / 100
    return max(0, min(1, percentile))


def valuation_risk_adjustment(valuation):
    if not valuation:
        return 0, []
    trend = valuation.get("trend", {})
    percentile = valuation_percentile_to_unit(trend.get("valuation_percentile"))
    current = safe_float(trend.get("current_value"))
    average = safe_float(trend.get("average_value"))
    reasons = []
    adjustment = 0

    if percentile is not None:
        if percentile >= 0.80:
            adjustment += 10
            reasons.append(f"估值处于历史高分位({percentile:.0%})，安全边际下降")
        elif percentile <= 0.25:
            adjustment -= 6
            reasons.append(f"估值处于历史低分位({percentile:.0%})，估值压力相对较低")

    if current > 0 and average > 0:
        premium = current / average - 1
        if premium >= 0.30:
            adjustment += 6
            reasons.append("当前估值明显高于历史均值")
        elif premium <= -0.25:
            adjustment -= 4
            reasons.append("当前估值低于历史均值较多")

    plate = valuation.get("plate_distribution", {})
    plate_rank = safe_float(plate.get("plate_ranking"))
    plate_count = safe_float(plate.get("plate_stock_item_count"))
    if plate_rank > 0 and plate_count > 0:
        rank_percentile = plate_rank / plate_count
        if rank_percentile <= 0.20:
            adjustment += 4
            reasons.append("估值在所属板块中排名偏高")
        elif rank_percentile >= 0.80:
            adjustment -= 2
            reasons.append("估值在所属板块中排名偏低")

    growth = valuation.get("profit_growth_rate", {})
    conclusion = str(growth.get("conclusion_detailed") or "")
    if conclusion:
        reasons.append(conclusion[:120])

    return adjustment, reasons


FINANCIAL_FIELD_KEYWORDS = {
    "revenue": ["营业总收入", "营业额", "total revenue", "revenue"],
    "gross_profit": ["毛利", "gross profit"],
    "operating_profit": ["营业利润", "经营利润", "operating profit", "operating income"],
    "net_income": ["归属母公司净利润", "净利润", "net income", "net profit"],
    "eps": ["基本每股收益", "稀释每股收益", "eps", "earnings per share"],
    "cash": ["现金", "cash"],
    "total_assets": ["总资产", "total assets"],
    "total_liabilities": ["总负债", "total liabilities"],
    "operating_cash_flow": ["经营现金流", "operating cash flow"],
}


def find_financial_item(report, keywords):
    for item in report.get("items", []) or []:
        name = str(item.get("display_name") or "").lower()
        if any(keyword.lower() in name for keyword in keywords):
            return item
    return None


def financial_summary(financials):
    if not financials:
        return {}
    reports = financials.get("reports", [])
    if not reports:
        return {}
    latest = reports[0]
    summary = {
        "latest_period": latest.get("period_text"),
        "latest_date": latest.get("date_time_str"),
        "currency_code": latest.get("currency_code"),
    }
    for key, keywords in FINANCIAL_FIELD_KEYWORDS.items():
        item = find_financial_item(latest, keywords)
        if item:
            summary[key] = safe_float(item.get("data"), None)
            summary[f"{key}_yoy"] = safe_float(item.get("yoy"), None)
            summary[f"{key}_qoq"] = safe_float(item.get("qoq"), None)
    return summary


def financial_risk_adjustment(financials):
    summary = financial_summary(financials)
    if not summary:
        return 0, []

    reasons = []
    adjustment = 0
    revenue_yoy = summary.get("revenue_yoy")
    net_income_yoy = summary.get("net_income_yoy")
    operating_profit_yoy = summary.get("operating_profit_yoy")
    operating_cash_flow = summary.get("operating_cash_flow")
    net_income = summary.get("net_income")

    if revenue_yoy is not None:
        if revenue_yoy < -10:
            adjustment += 8
            reasons.append("最近财报收入同比下滑超过10%")
        elif revenue_yoy > 10:
            adjustment -= 4
            reasons.append("最近财报收入同比增长超过10%")

    if net_income_yoy is not None:
        if net_income_yoy < -20:
            adjustment += 8
            reasons.append("最近财报净利润同比明显下滑")
        elif net_income_yoy > 20:
            adjustment -= 4
            reasons.append("最近财报净利润同比增长较强")

    if operating_profit_yoy is not None and operating_profit_yoy < -20:
        adjustment += 5
        reasons.append("营业利润同比明显走弱")

    if operating_cash_flow is not None and net_income is not None and net_income > 0 and operating_cash_flow < 0:
        adjustment += 6
        reasons.append("净利润为正但经营现金流为负，盈利质量需要谨慎")

    return adjustment, reasons


def score_position(
    position,
    daily_frame,
    portfolio_value,
    weights,
    meta,
    plates=None,
    valuation=None,
    financials=None,
):
    code = position.get("code", "")
    plates = plates or []
    sector = "ETF" if position.get("is_etf") else classify_sector(code, meta, plates)
    size_tier = infer_size_tier(code, meta, plates)
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
    vol_tier = volatility_tier(vol60)
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
    size_addon = 8 if size_tier == "small_cap" else 0
    volatility_addon = 10 if vol_tier == "extreme" else 5 if vol_tier == "high" else 0
    valuation_addon, valuation_reasons = valuation_risk_adjustment(valuation)
    financial_addon, financial_reasons = financial_risk_adjustment(financials)
    risk_score = (
        volatility_risk * weights["volatility"]
        + drawdown_risk * weights["drawdown"]
        + concentration_risk * weights["position_weight"]
        + speculative_addon
        + size_addon
        + volatility_addon
        + valuation_addon
        + financial_addon
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
    if size_tier == "small_cap":
        reasons.append("小盘/投机属性较强，更适合分批处理而不是一次性加仓")
    if vol_tier in ("high", "extreme"):
        reasons.append("历史K线显示波动率偏高，仓位上限应低于普通大盘股")
    reasons.extend(valuation_reasons)
    reasons.extend(financial_reasons)

    return {
        "code": code,
        "name": position.get("name", ""),
        "sector": sector,
        "theme": meta.get(code, {}).get("theme", []) + plate_names(plates)[:5],
        "profile": {
            "risk_tier": risk_tier or "normal",
            "size_tier": size_tier,
            "volatility_tier": vol_tier,
            "plates": plates,
            "valuation": valuation,
            "financials": financial_summary(financials),
        },
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
                "volatility_tier": vol_tier,
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


def sync_advisor_profiles(force=False):
    positions_result = get_positions()
    if not positions_result.get("ok"):
        return positions_result
    codes = [
        item["code"]
        for item in positions_result.get("positions", [])
        if item.get("code") and not item.get("is_etf")
    ]
    plate_result = sync_owner_plates(codes, force=force)
    valuation_result = sync_valuations(codes, force=force)
    financial_result = sync_financials(codes, force=force)
    return {
        "ok": plate_result.get("ok") and valuation_result.get("ok") and financial_result.get("ok"),
        "count": (
            plate_result.get("count", 0)
            + valuation_result.get("count", 0)
            + financial_result.get("count", 0)
        ),
        "plates": plate_result,
        "valuations": valuation_result,
        "financials": financial_result,
    }


def build_advisor_report(force_sync=False):
    state = load_advisor_state()
    meta = load_symbol_meta()
    positions_result = get_positions()
    if not positions_result.get("ok"):
        return positions_result

    positions = positions_result.get("positions", [])
    codes = [
        item.get("code")
        for item in positions
        if item.get("code") and not item.get("is_etf")
    ]
    owner_plates = get_owner_plates(codes)
    valuations = get_valuations(codes)
    financials = get_financials(codes)
    if force_sync:
        for position in positions:
            code = position.get("code")
            if code:
                sync_all_period_klines(code, force=True)
        owner_plates = get_owner_plates(codes, force=True)
        valuations = get_valuations(codes, force=True)
        financials = get_financials(codes, force=True)

    portfolio_value = sum(safe_float(item.get("market_val")) for item in positions)
    reports = []
    for position in positions:
        code = position.get("code")
        if not code:
            continue
        frame = get_daily_klines(code)
        reports.append(score_position(
            position,
            frame,
            portfolio_value,
            state["weights"],
            meta,
            plates=owner_plates.get(code, []),
            valuation=valuations.get(code),
            financials=financials.get(code),
        ))

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
