import json
import math
import os
from datetime import datetime, timedelta, timezone

import pandas as pd
from moomoo import *

from advisor_kline_cache import (
    get_daily_klines,
    get_period_klines,
    sync_all_period_klines,
    sync_daily_klines,
)
from advisor_profile import (
    get_capital_distributions,
    get_capital_flows,
    get_company_profiles,
    get_daily_short_volumes,
    get_earnings_moves,
    get_financials,
    get_insider_holders,
    get_insider_trades,
    get_operational_efficiency,
    get_owner_plates,
    get_shareholders_changes,
    get_shareholders_overviews,
    get_short_interests,
    get_valuations,
    sync_insider_holders,
    sync_insider_trades,
    sync_capital_distributions,
    sync_capital_flows,
    sync_company_profiles,
    sync_daily_short_volumes,
    sync_earnings_moves,
    sync_financials,
    sync_operational_efficiency,
    sync_owner_plates,
    sync_shareholders_changes,
    sync_shareholders_overviews,
    sync_short_interests,
    sync_valuations,
)
from config import DATA_DIR, HOST, PORT
from asset_snapshots import get_latest_closed_trading_date
from routes.positions import get_positions


ADVISOR_STATE_FILE = DATA_DIR / "advisor_state.json"
ADVISOR_REPORT_FILE = DATA_DIR / "advisor_report.json"
SYMBOL_META_FILE = DATA_DIR / "advisor_symbol_meta.json"
ADVISOR_WATCHLIST_FILE = DATA_DIR / "advisor_watchlist.json"
ADVISOR_ALERT_ACKS_FILE = DATA_DIR / "advisor_alert_acks.json"
ADVISOR_TRIGGER_ALERTS_FILE = DATA_DIR / "advisor_trigger_alerts.json"

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


def normalize_symbol(code):
    symbol = str(code or "").strip().upper()
    if not symbol:
        return ""
    if "." in symbol:
        return symbol
    return f"US.{symbol}"


def load_watchlist():
    payload = read_json(ADVISOR_WATCHLIST_FILE, {})
    payload.setdefault("updated_at", utc_now_iso())
    payload.setdefault("symbols", {})
    return payload


def save_watchlist(payload):
    payload["updated_at"] = utc_now_iso()
    write_json(ADVISOR_WATCHLIST_FILE, payload)


def load_alert_acks():
    payload = read_json(ADVISOR_ALERT_ACKS_FILE, {})
    payload.setdefault("acknowledged_ids", [])
    return payload


def save_alert_acks(payload):
    payload["updated_at"] = utc_now_iso()
    write_json(ADVISOR_ALERT_ACKS_FILE, payload)


def load_trigger_alerts():
    payload = read_json(ADVISOR_TRIGGER_ALERTS_FILE, {})
    payload.setdefault("updated_at", utc_now_iso())
    payload.setdefault("alerts", [])
    return payload


def save_trigger_alerts(payload):
    payload["updated_at"] = utc_now_iso()
    write_json(ADVISOR_TRIGGER_ALERTS_FILE, payload)


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
    data["ma5"] = close.rolling(5).mean()
    data["ma20"] = close.rolling(20).mean()
    data["ma60"] = close.rolling(60).mean()
    data["ma120"] = close.rolling(120).mean()
    data["ret_1d"] = close.pct_change()
    data["ret_5d"] = close.pct_change(5)
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
    data["macd_hist"] = data["macd"] - data["macd_signal"]

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


def indicator_ready(latest):
    required = ["ma5", "ma20", "ma60", "rsi14", "macd", "macd_signal", "macd_hist", "volatility_60d", "ret_20d"]
    return all(pd.notna(latest.get(name)) for name in required)


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


def recent_swing_points(frame, column, mode="low", window=2, limit=8):
    if frame.empty or column not in frame.columns:
        return []
    data = frame.tail(140).reset_index(drop=True)
    points = []
    for idx in range(window, len(data) - window):
        value = safe_float(data.loc[idx, column], None)
        if value is None:
            continue
        nearby = data.loc[idx - window:idx + window, column].dropna()
        if nearby.empty:
            continue
        if mode == "low" and value <= safe_float(nearby.min(), value):
            points.append({"date": str(data.loc[idx, "date"]), "value": value})
        elif mode == "high" and value >= safe_float(nearby.max(), value):
            points.append({"date": str(data.loc[idx, "date"]), "value": value})
    return points[-limit:]


def rising_sequence(points, tolerance=0.01):
    if len(points) < 3:
        return False
    values = [safe_float(item.get("value")) for item in points[-3:]]
    return values[2] >= values[1] * (1 - tolerance) and values[1] >= values[0] * (1 - tolerance)


def falling_sequence(points, tolerance=0.01):
    if len(points) < 3:
        return False
    values = [safe_float(item.get("value")) for item in points[-3:]]
    return values[2] <= values[1] * (1 + tolerance) and values[1] <= values[0] * (1 + tolerance)


def price_structure_analysis(frame, latest):
    if frame.empty:
        return {
            "status": "unknown",
            "score": 0,
            "points": [],
            "swing_lows": [],
            "swing_highs": [],
        }
    data = frame.copy().sort_values("date")
    close = safe_float(latest.get("close"))
    recent = data.tail(60)
    lows = recent_swing_points(data, "low", mode="low")
    highs = recent_swing_points(data, "high", mode="high")
    higher_lows = rising_sequence(lows)
    higher_highs = rising_sequence(highs)
    lower_lows = falling_sequence(lows)
    lower_highs = falling_sequence(highs)
    recent_high_20 = safe_float(data.tail(20)["high"].max())
    recent_low_20 = safe_float(data.tail(20)["low"].min())
    recent_high_60 = safe_float(recent["high"].max())
    recent_low_60 = safe_float(recent["low"].min())
    volume = safe_float(latest.get("volume"), None)
    avg_volume_20 = safe_float(data.tail(20)["volume"].mean(), None) if "volume" in data.columns else None
    range_20 = (recent_high_20 - recent_low_20) / close if close > 0 else 0
    range_60 = (recent_high_60 - recent_low_60) / close if close > 0 else 0
    breakout_20 = close > recent_high_20 * 0.995 if recent_high_20 > 0 else False
    breakdown_20 = close < recent_low_20 * 1.005 if recent_low_20 > 0 else False
    volume_expansion = volume is not None and avg_volume_20 and volume >= avg_volume_20 * 1.3

    score = 0
    points = []
    if higher_lows:
        score += 18
        points.append("近阶段低点不断抬高，承接在增强")
    if higher_highs:
        score += 14
        points.append("近阶段高点同步抬高，趋势结构偏多")
    if lower_lows:
        score -= 18
        points.append("近阶段低点下移，趋势结构仍偏弱")
    if lower_highs:
        score -= 12
        points.append("反弹高点下移，上方抛压仍在")
    if breakout_20 and volume_expansion:
        score += 16
        points.append("接近/突破20日高位且成交量放大")
    elif breakout_20:
        score += 8
        points.append("价格接近/突破20日高位，但量能确认一般")
    if breakdown_20:
        score -= 14
        points.append("价格靠近/跌破20日低位，短期结构走弱")
    if 0 < range_20 < range_60 * 0.45:
        score += 5
        points.append("20日振幅相对收窄，可能进入蓄势区")

    if score >= 22:
        status = "constructive"
    elif score >= 8:
        status = "improving"
    elif score <= -20:
        status = "damaged"
    elif score <= -8:
        status = "weakening"
    else:
        status = "neutral"

    return {
        "status": status,
        "score": round(score, 2),
        "points": points,
        "swing_lows": lows[-4:],
        "swing_highs": highs[-4:],
        "recent_high_20": round(recent_high_20, 4),
        "recent_low_20": round(recent_low_20, 4),
        "range_20": round(range_20, 4),
        "range_60": round(range_60, 4),
        "volume_expansion": bool(volume_expansion),
    }


def stock_personality_profile(code, size_tier, risk_tier, vol_tier, plates, ret20, ret60, rsi, price_structure, daily_short_volume, short_interest):
    names = " ".join(plate_names(plates)).lower()
    short_volume = daily_short_volume_summary(daily_short_volume)
    short_summary = short_interest_summary(short_interest)
    short_percent = safe_float(short_volume.get("latest_short_percent"), 0)
    days_to_cover = safe_float(short_summary.get("days_to_cover"), 0)
    traits = []

    speculative = risk_tier == "speculative" or size_tier == "small_cap" or vol_tier in ("high", "extreme")
    squeeze = short_percent >= 30 or days_to_cover >= 3
    momentum = ret20 > 0.12 and ret60 > 0
    reversal = price_structure.get("status") in ("constructive", "improving") and ret60 < 0
    mega_or_quality = size_tier == "large_cap" or any(word in names for word in ["mega", "large cap", "大盘", "nasdaq", "s&p"])

    if speculative:
        traits.append("高波动/投机属性")
    if squeeze:
        traits.append("空头拥挤或轧空敏感")
    if momentum:
        traits.append("趋势动量型")
    if reversal:
        traits.append("反转修复型")
    if mega_or_quality:
        traits.append("大盘/质量权重型")

    if speculative:
        profile_type = "speculative_momentum"
        rsi_hot = 84 if squeeze else 80
        max_buy_percent = 5 if vol_tier == "extreme" else 10
        trim_bias = 8
        note = "这类股票不能用普通蓝筹的RSI阈值，但仓位和止盈要更严格。"
    elif mega_or_quality:
        profile_type = "quality_trend"
        rsi_hot = 74
        max_buy_percent = 15
        trim_bias = 0
        note = "这类股票更看重趋势延续、估值和财务质量，允许更平滑地分批。"
    else:
        profile_type = "standard"
        rsi_hot = 76
        max_buy_percent = 10
        trim_bias = 3
        note = "按普通趋势/风险模型处理，等待技术和资金面相互确认。"

    return {
        "type": profile_type,
        "traits": traits or ["普通趋势型"],
        "speculative": speculative,
        "short_squeeze_sensitive": squeeze,
        "rsi_hot_threshold": rsi_hot,
        "max_buy_percent": max_buy_percent,
        "trim_bias": trim_bias,
        "current_rsi_state": "overheated" if rsi >= rsi_hot else "hot" if rsi >= rsi_hot - 6 else "normal",
        "strategy_note": note,
    }


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


def earnings_summary(earnings):
    if not earnings:
        return {}
    return earnings.get("summary", {}) or {}


def earnings_risk_adjustment(earnings):
    summary = earnings_summary(earnings)
    if not summary:
        return 0, []

    reasons = []
    adjustment = 0
    max_move = safe_float(summary.get("avg_max_abs_move_5d"))
    post_5d = safe_float(summary.get("avg_5d_return_after_earnings"))
    iv_crush = safe_float(summary.get("latest_option_iv_crush"))
    predict_vola = safe_float(summary.get("latest_predict_vola_ratio"))

    if max_move >= 0.12:
        adjustment += 8
        reasons.append("历史财报日前后5个交易日平均波动较大")
    elif max_move >= 0.07:
        adjustment += 4
        reasons.append("历史财报日前后存在中等波动风险")

    if post_5d <= -0.06:
        adjustment += 5
        reasons.append("历史财报后5日平均表现偏弱")
    elif post_5d >= 0.06:
        adjustment -= 3
        reasons.append("历史财报后5日平均表现偏强")

    if iv_crush >= 20:
        adjustment += 3
        reasons.append("历史/当前期权IV crush较高，财报事件波动定价较重")

    if predict_vola >= 10:
        adjustment += 3
        reasons.append("最新财报预期波动比例较高")

    return adjustment, reasons


def company_profile_summary(company_profile):
    if not company_profile:
        return {}
    return {
        "company_name": company_profile.get("company_name"),
        "listed_date": company_profile.get("listed_date"),
        "founded_date": company_profile.get("founded_date"),
        "market": company_profile.get("market"),
        "employee_num": company_profile.get("employee_num"),
        "website": company_profile.get("website"),
        "business": company_profile.get("business"),
        "description": company_profile.get("description"),
    }


def operational_efficiency_summary(operational_efficiency):
    if not operational_efficiency:
        return {}
    latest = operational_efficiency.get("latest", {}) or {}
    return {
        "currency_code": operational_efficiency.get("currency_code"),
        "period_text": latest.get("period_text"),
        "end_date_str": latest.get("end_date_str"),
        "employee_num": safe_float(latest.get("employee_num"), None),
        "employee_num_yoy": safe_float(latest.get("employee_num_yoy"), None),
        "income_per_capita": safe_float(latest.get("income_per_capita"), None),
        "income_per_capita_yoy": safe_float(latest.get("income_per_capita_yoy"), None),
        "profit_per_capita": safe_float(latest.get("profit_per_capita"), None),
        "profit_per_capita_yoy": safe_float(latest.get("profit_per_capita_yoy"), None),
        "net_profit_per_capita": safe_float(latest.get("net_profit_per_capita"), None),
        "net_profit_per_capita_yoy": safe_float(latest.get("net_profit_per_capita_yoy"), None),
    }


def operational_efficiency_risk_adjustment(operational_efficiency):
    summary = operational_efficiency_summary(operational_efficiency)
    if not summary:
        return 0, []

    adjustment = 0
    reasons = []
    income_yoy = summary.get("income_per_capita_yoy")
    profit_yoy = summary.get("profit_per_capita_yoy")
    net_profit_yoy = summary.get("net_profit_per_capita_yoy")
    employee_yoy = summary.get("employee_num_yoy")

    if income_yoy is not None:
        if income_yoy > 10:
            adjustment -= 3
            reasons.append("人均营收同比改善，经营效率增强")
        elif income_yoy < -10:
            adjustment += 4
            reasons.append("人均营收同比下滑，经营效率走弱")

    if profit_yoy is not None:
        if profit_yoy > 15:
            adjustment -= 4
            reasons.append("人均营业利润同比改善")
        elif profit_yoy < -15:
            adjustment += 5
            reasons.append("人均营业利润同比下滑明显")

    if net_profit_yoy is not None:
        if net_profit_yoy > 15:
            adjustment -= 4
            reasons.append("人均净利润同比改善")
        elif net_profit_yoy < -15:
            adjustment += 5
            reasons.append("人均净利润同比下滑明显")

    if employee_yoy is not None and employee_yoy > 15 and income_yoy is not None and income_yoy < 0:
        adjustment += 4
        reasons.append("员工扩张较快但人均营收下降，扩张质量需观察")

    return adjustment, reasons


def capital_flow_summary(capital_flow):
    return (capital_flow or {}).get("summary", {}) or {}


def capital_distribution_summary(capital_distribution):
    return (capital_distribution or {}).get("summary", {}) or {}


def capital_risk_adjustment(capital_flow, capital_distribution):
    flow = capital_flow_summary(capital_flow)
    distribution = capital_distribution_summary(capital_distribution)
    adjustment = 0
    reasons = []

    in_flow_20 = safe_float(flow.get("in_flow_20"), None)
    main_in_flow_20 = safe_float(flow.get("main_in_flow_20"), None)
    main_net = safe_float(distribution.get("main_net"), None)
    small_net = safe_float(distribution.get("small_net"), None)

    if in_flow_20 is not None:
        if in_flow_20 < 0:
            adjustment += 4
            reasons.append("近20期资金整体净流出")
        elif in_flow_20 > 0:
            adjustment -= 2
            reasons.append("近20期资金整体净流入")

    if main_in_flow_20 is not None:
        if main_in_flow_20 < 0:
            adjustment += 5
            reasons.append("近20期主力资金净流出")
        elif main_in_flow_20 > 0:
            adjustment -= 3
            reasons.append("近20期主力资金净流入")

    if main_net is not None and main_net < 0:
        adjustment += 3
        reasons.append("最新资金分布显示大单/特大单净流出")
    elif main_net is not None and main_net > 0:
        adjustment -= 2
        reasons.append("最新资金分布显示大单/特大单净流入")

    if main_net is not None and small_net is not None and main_net < 0 < small_net:
        adjustment += 3
        reasons.append("主力净流出但小单净流入，筹码结构需谨慎")

    return adjustment, reasons


def daily_short_volume_summary(daily_short_volume):
    return (daily_short_volume or {}).get("summary", {}) or {}


def short_interest_summary(short_interest):
    return (short_interest or {}).get("summary", {}) or {}


def short_risk_adjustment(daily_short_volume, short_interest):
    volume = daily_short_volume_summary(daily_short_volume)
    interest = short_interest_summary(short_interest)
    adjustment = 0
    reasons = []

    short_percent_20 = safe_float(volume.get("avg_short_percent_20"), None)
    latest_short_percent = safe_float(volume.get("latest_short_percent"), None)
    days_to_cover = safe_float(interest.get("days_to_cover"), None)
    interest_change = safe_float(interest.get("short_change_vs_previous"), None)
    interest_percent = safe_float(interest.get("short_percent"), None)

    if short_percent_20 is not None:
        if short_percent_20 >= 45:
            adjustment += 6
            reasons.append("近20期卖空成交比例偏高")
        elif short_percent_20 >= 30:
            adjustment += 3
            reasons.append("近20期卖空成交比例中等偏高")

    if latest_short_percent is not None and short_percent_20 is not None and latest_short_percent > short_percent_20 + 10:
        adjustment += 3
        reasons.append("最新卖空比例高于近期均值")

    if days_to_cover is not None:
        if days_to_cover >= 5:
            adjustment += 5
            reasons.append("空头回补天数较高，波动和轧空风险都上升")
        elif days_to_cover >= 3:
            adjustment += 3
            reasons.append("空头回补天数中等偏高")

    if interest_change is not None:
        if interest_change >= 0.15:
            adjustment += 5
            reasons.append("空头持仓较上期明显增加")
        elif interest_change <= -0.15:
            adjustment -= 3
            reasons.append("空头持仓较上期明显下降")

    if interest_percent is not None and interest_percent >= 10:
        adjustment += 4
        reasons.append("空头持仓比例偏高")

    return adjustment, reasons


def shareholders_overview_summary(shareholders_overview):
    return (shareholders_overview or {}).get("summary", {}) or {}


def shareholders_changes_summary(shareholders_changes):
    return (shareholders_changes or {}).get("summary", {}) or {}


def shareholders_risk_adjustment(shareholders_overview, shareholders_changes):
    overview = shareholders_overview_summary(shareholders_overview)
    changes = shareholders_changes_summary(shareholders_changes)
    adjustment = 0
    reasons = []

    top_holder_pct = safe_float(overview.get("top_holder_pct"), None)
    top5_pct = safe_float(overview.get("top5_holder_pct"), None)
    net_change = safe_float(changes.get("net_share_ratio_change"), None)
    negative_count = safe_float(changes.get("negative_change_count"), None)
    positive_count = safe_float(changes.get("positive_change_count"), None)
    largest_sell = safe_float(changes.get("largest_sell_share_ratio_change"), None)

    if top_holder_pct is not None and top_holder_pct >= 40:
        adjustment += 3
        reasons.append("第一大股东持股占比较高，治理和流动性集中风险需关注")
    if top5_pct is not None and top5_pct >= 65:
        adjustment += 3
        reasons.append("前五大股东持股集中度偏高")

    if net_change is not None:
        if net_change >= 0.3:
            adjustment -= 3
            reasons.append("近期主要股东整体增持")
        elif net_change <= -0.3:
            adjustment += 4
            reasons.append("近期主要股东整体减持")

    if largest_sell is not None and largest_sell <= -0.5:
        adjustment += 3
        reasons.append("单一主要股东减持幅度较大")

    if negative_count is not None and positive_count is not None and negative_count > positive_count * 1.5:
        adjustment += 2
        reasons.append("减持记录数量明显多于增持记录")

    return adjustment, reasons


def insider_trades_summary(insider_trades):
    return (insider_trades or {}).get("summary", {}) or {}


def insider_holders_summary(insider_holders):
    return (insider_holders or {}).get("summary", {}) or {}


def insider_risk_adjustment(insider_trades, insider_holders):
    trades = insider_trades_summary(insider_trades)
    holders = insider_holders_summary(insider_holders)
    adjustment = 0
    reasons = []

    if trades.get("unsupported") or holders.get("unsupported"):
        return adjustment, reasons

    sell_count = safe_float(trades.get("sell_count"), 0)
    buy_count = safe_float(trades.get("buy_count"), 0)
    proposed_sale_count = safe_float(trades.get("proposed_sale_count"), 0)
    net_trade_shares = safe_float(trades.get("net_trade_shares"), None)
    bought_count = safe_float(holders.get("insider_bought_count"), None)
    sold_count = safe_float(holders.get("insider_sold_count"), None)

    if sell_count > buy_count * 2 and sell_count >= 3:
        adjustment += 5
        reasons.append("近期内部人卖出记录明显多于买入")
    elif buy_count > sell_count and buy_count >= 2:
        adjustment -= 3
        reasons.append("近期内部人买入记录多于卖出")

    if proposed_sale_count >= 2:
        adjustment += 3
        reasons.append("存在多笔内部人意向出售记录")

    if net_trade_shares is not None:
        if net_trade_shares < 0:
            adjustment += 3
            reasons.append("内部人交易净卖出")
        elif net_trade_shares > 0:
            adjustment -= 2
            reasons.append("内部人交易净买入")

    if bought_count is not None and sold_count is not None and sold_count > bought_count:
        adjustment += 2
        reasons.append("内部人统计显示卖出人数多于买入人数")

    return adjustment, reasons


def nearest_above(values, current):
    candidates = sorted(value for value in values if value and value > current)
    return candidates[0] if candidates else 0


def nearest_below(values, current):
    candidates = sorted((value for value in values if value and value < current), reverse=True)
    return candidates[0] if candidates else 0


def position_trade_plan(position, action, risk_score, technical_score, weight, volatility_tier, close, daily_frame, levels=None, confirmed=False, personality=None):
    qty = safe_float(position.get("qty"))
    unrealized_pl = safe_float(position.get("unrealized_pl"))
    pl_ratio = safe_float(position.get("pl_ratio"))
    sell_pct = 0
    buy_pct = 0
    alert_type = None
    trigger_price = None
    trigger_condition = None
    recent_high = 0
    recent_low = 0
    levels = levels or {}
    personality = personality or {}
    if not daily_frame.empty:
        recent_high = safe_float(daily_frame.tail(20)["high"].max())
        recent_low = safe_float(daily_frame.tail(20)["low"].min())
    resistance_levels = [
        recent_high,
        safe_float(levels.get("boll_upper")),
        close + safe_float(levels.get("atr14")),
        close * 1.03 if close > 0 else 0,
    ]
    support_levels = [
        safe_float(levels.get("ma5")),
        safe_float(levels.get("ma20")),
        safe_float(levels.get("ma60")),
        safe_float(levels.get("boll_mid")),
        recent_low,
        close - safe_float(levels.get("atr14")),
    ]

    if not confirmed:
        return {
            "alert_type": None,
            "buy_percent": 0,
            "sell_percent": 0,
            "sell_qty": 0,
            "trigger_price": None,
            "trigger_condition": None,
            "basis": "核心技术指标未确认，暂不生成买卖触发价",
        }

    if action == "trim":
        sell_pct = 20
        if risk_score >= 82:
            sell_pct = 30
        elif risk_score < 72:
            sell_pct = 15
        if weight >= 0.30:
            sell_pct += 5
        if volatility_tier in ("high", "extreme"):
            sell_pct += 5
        if pl_ratio > 0.35 or unrealized_pl > 0:
            sell_pct += 5
        alert_type = "sell"
        target = nearest_above(resistance_levels, close)
        if not target and close > 0:
            target = close * 1.03
        trigger_price = round(target, 4) if target > 0 else None
        trigger_condition = "price_at_or_above"
    elif action == "reduce_or_watch":
        sell_pct = 10
        if risk_score >= 65:
            sell_pct = 20
        if technical_score < 35:
            sell_pct += 5
        alert_type = "sell"
        target = nearest_above([safe_float(levels.get("ma5")), safe_float(levels.get("ma20")), close * 1.015], close)
        if not target and close > 0:
            target = close * 1.015
        trigger_price = round(target, 4) if target > 0 else None
        trigger_condition = "price_at_or_above"
    elif action == "add_candidate":
        buy_pct = 10
        if technical_score >= 78 and risk_score < 45:
            buy_pct = 15
        if volatility_tier in ("high", "extreme"):
            buy_pct = max(5, buy_pct - 5)
        max_buy_percent = safe_float(personality.get("max_buy_percent"), None)
        if max_buy_percent is not None and max_buy_percent > 0:
            buy_pct = min(buy_pct, int(max_buy_percent))
        alert_type = "buy"
        target = nearest_below(support_levels, close)
        if not target and close > 0:
            target = close * 0.985
        trigger_price = round(target, 4) if target > 0 else None
        trigger_condition = "price_at_or_below"

    sell_pct = int(max(0, min(50, sell_pct)))
    buy_pct = int(max(0, min(20, buy_pct)))
    sell_qty = round(qty * sell_pct / 100, 6) if sell_pct else 0
    return {
        "alert_type": alert_type,
        "buy_percent": buy_pct,
        "sell_percent": sell_pct,
        "sell_qty": sell_qty,
        "trigger_price": trigger_price,
        "trigger_condition": trigger_condition,
        "basis": "基于当前仓位、浮盈亏、波动率、裸K结构、技术面、股票性格和组合集中度的分批建议",
    }


def price_scale_guard(position, kline_close):
    qty = safe_float(position.get("qty"))
    market_val = safe_float(position.get("market_val"))
    position_price = market_val / qty if qty > 0 else 0
    if position_price <= 0 or kline_close <= 0:
        return {
            "ok": True,
            "position_price": position_price,
            "ratio": None,
            "reason": None,
        }
    ratio = max(position_price, kline_close) / min(position_price, kline_close)
    if ratio >= 3:
        return {
            "ok": False,
            "position_price": position_price,
            "ratio": round(ratio, 4),
            "reason": "持仓真实单价与日K价格差异过大，可能是复权/拆股/币种口径不一致，已禁止生成交易触发价",
        }
    return {
        "ok": True,
        "position_price": position_price,
        "ratio": round(ratio, 4),
        "reason": None,
    }


def make_analysis_points(
    *,
    price_structure,
    personality,
    close,
    ma5,
    ma20,
    ma60,
    rsi,
    macd,
    macd_signal,
    macd_hist,
    prev_macd_hist,
    vol60,
    ret20,
    ret60,
    atr14,
    boll_mid,
    boll_upper,
    boll_lower,
    capital_flow,
    capital_distribution,
    daily_short_volume,
    short_interest,
    valuation,
    shareholders_changes,
    shareholders_overview,
    insider_trades,
    insider_holders,
    financials,
    earnings,
    operational_efficiency,
):
    points = []
    points.append({
        "category": "profile",
        "label": "股票性格",
        "status": personality.get("type", "standard"),
        "detail": f"{', '.join(personality.get('traits', []))}; {personality.get('strategy_note', '')}",
    })

    points.append({
        "category": "price_action",
        "label": "裸K结构",
        "status": price_structure.get("status", "unknown"),
        "detail": "；".join(price_structure.get("points", [])[:3]) or "裸K结构暂未出现明确方向",
    })

    ma_stack = "bullish" if ma5 > ma20 > ma60 > 0 else "bearish" if ma5 < ma20 < ma60 and ma60 > 0 else "mixed"
    points.append({
        "category": "technical",
        "label": "均线结构",
        "status": ma_stack,
        "detail": f"MA5={ma5:.4f}, MA20={ma20:.4f}, MA60={ma60:.4f}",
    })

    if macd > macd_signal and macd_hist > 0:
        macd_status = "bullish"
        macd_detail = "MACD在信号线上方，柱体为正"
    elif macd < macd_signal and macd_hist < 0:
        macd_status = "bearish"
        macd_detail = "MACD在信号线下方，柱体为负"
    else:
        macd_status = "mixed"
        macd_detail = "MACD未形成明确方向"
    if macd_hist > prev_macd_hist:
        macd_detail += "，柱体改善"
    elif macd_hist < prev_macd_hist:
        macd_detail += "，柱体走弱"
    points.append({
        "category": "technical",
        "label": "MACD",
        "status": macd_status,
        "detail": macd_detail,
    })

    rsi_status = "overheated" if rsi >= 75 else "weak" if rsi <= 35 else "healthy" if 45 <= rsi <= 68 else "neutral"
    points.append({
        "category": "technical",
        "label": "RSI",
        "status": rsi_status,
        "detail": f"RSI14={rsi:.2f}",
    })

    boll_status = "breakout_watch" if close > boll_upper > 0 else "support_watch" if close < boll_lower and boll_lower > 0 else "inside_band"
    points.append({
        "category": "technical",
        "label": "布林带",
        "status": boll_status,
        "detail": f"中轨={boll_mid:.4f}, 上轨={boll_upper:.4f}, 下轨={boll_lower:.4f}",
    })

    points.append({
        "category": "technical",
        "label": "波动/趋势",
        "status": volatility_tier(vol60),
        "detail": f"20日涨跌={ret20:.2%}, 60日涨跌={ret60:.2%}, ATR14={atr14:.4f}",
    })

    flow = capital_flow_summary(capital_flow)
    distribution = capital_distribution_summary(capital_distribution)
    main_flow = safe_float(flow.get("main_in_flow_20"), None)
    main_net = safe_float(distribution.get("main_net"), None)
    if main_flow is not None or main_net is not None:
        points.append({
            "category": "capital",
            "label": "资金流",
            "status": "inflow" if (main_flow or 0) > 0 or (main_net or 0) > 0 else "outflow",
            "detail": f"20期主力净流={main_flow}, 最新大单/特大单净额={main_net}",
        })

    short_volume = daily_short_volume_summary(daily_short_volume)
    short_summary = short_interest_summary(short_interest)
    latest_short = safe_float(short_volume.get("latest_short_percent"), None)
    avg_short = safe_float(short_volume.get("avg_short_percent_20"), None)
    days_to_cover = safe_float(short_summary.get("days_to_cover"), None)
    if latest_short is not None or avg_short is not None or days_to_cover is not None:
        points.append({
            "category": "short",
            "label": "卖空/空头",
            "status": "high_pressure" if (latest_short or 0) >= 30 or (days_to_cover or 0) >= 3 else "normal",
            "detail": f"最新卖空比例={latest_short}, 20期均值={avg_short}, 回补天数={days_to_cover}",
        })

    val = valuation or {}
    trend = val.get("trend", {}) if val else {}
    percentile = valuation_percentile_to_unit(trend.get("valuation_percentile"))
    if trend:
        points.append({
            "category": "valuation",
            "label": "估值",
            "status": "expensive" if percentile is not None and percentile >= 0.8 else "cheap" if percentile is not None and percentile <= 0.25 else "neutral",
            "detail": f"当前估值={trend.get('current_value')}, 历史均值={trend.get('average_value')}, 分位={None if percentile is None else round(percentile, 4)}",
        })

    holders = shareholders_overview_summary(shareholders_overview)
    if holders:
        points.append({
            "category": "holders",
            "label": "持股集中度",
            "status": "concentrated" if safe_float(holders.get("top5_holder_pct"), 0) >= 65 else "normal",
            "detail": f"第一大股东={holders.get('top_holder_pct')}, 前五大={holders.get('top5_holder_pct')}",
        })

    changes = shareholders_changes_summary(shareholders_changes)
    net_holder_change = safe_float(changes.get("net_share_ratio_change"), None)
    if net_holder_change is not None:
        points.append({
            "category": "holders",
            "label": "主要股东变动",
            "status": "accumulation" if net_holder_change > 0 else "distribution" if net_holder_change < 0 else "flat",
            "detail": f"主要股东净变动比例={net_holder_change}",
        })

    insider = insider_trades_summary(insider_trades)
    insider_holder = insider_holders_summary(insider_holders)
    if (insider or insider_holder) and not insider.get("unsupported") and not insider_holder.get("unsupported"):
        points.append({
            "category": "insider",
            "label": "内部人交易",
            "status": "buying" if safe_float(insider.get("net_trade_shares")) > 0 else "selling" if safe_float(insider.get("net_trade_shares")) < 0 else "neutral",
            "detail": f"买入次数={insider.get('buy_count')}, 卖出次数={insider.get('sell_count')}, 净股数={insider.get('net_trade_shares')}, 内部人持股={insider_holder.get('total_holder_pct')}",
        })

    fin = financial_summary(financials)
    if fin:
        points.append({
            "category": "fundamental",
            "label": "财务",
            "status": "improving" if safe_float(fin.get("revenue_yoy"), 0) > 10 or safe_float(fin.get("net_income_yoy"), 0) > 20 else "watch",
            "detail": f"收入同比={fin.get('revenue_yoy')}, 净利润同比={fin.get('net_income_yoy')}, 期间={fin.get('latest_period')}",
        })

    efficiency = operational_efficiency_summary(operational_efficiency)
    if efficiency:
        points.append({
            "category": "fundamental",
            "label": "经营效率",
            "status": "improving" if safe_float(efficiency.get("income_per_capita_yoy"), 0) > 10 or safe_float(efficiency.get("net_profit_per_capita_yoy"), 0) > 15 else "watch",
            "detail": f"人均营收同比={efficiency.get('income_per_capita_yoy')}, 人均净利润同比={efficiency.get('net_profit_per_capita_yoy')}",
        })

    earn = earnings_summary(earnings)
    if earn:
        points.append({
            "category": "earnings",
            "label": "财报波动",
            "status": "volatile" if safe_float(earn.get("avg_max_abs_move_5d")) >= 0.12 else "normal",
            "detail": f"财报后5日平均收益={earn.get('avg_5d_return_after_earnings')}, 平均最大波动={earn.get('avg_max_abs_move_5d')}",
        })
    return points


def score_position(
    position,
    daily_frame,
    portfolio_value,
    weights,
    meta,
    plates=None,
    valuation=None,
    financials=None,
    earnings=None,
    company_profile=None,
    operational_efficiency=None,
    capital_flow=None,
    capital_distribution=None,
    daily_short_volume=None,
    short_interest=None,
    shareholders_overview=None,
    shareholders_changes=None,
    insider_trades=None,
    insider_holders=None,
):
    code = position.get("code", "")
    plates = plates or []
    sector = "ETF" if position.get("is_etf") else classify_sector(code, meta, plates)
    size_tier = infer_size_tier(code, meta, plates)
    market_val = safe_float(position.get("market_val"))
    weight = market_val / portfolio_value if portfolio_value > 0 else 0
    indicators = add_indicators(daily_frame)
    try:
        weekly_source = get_period_klines(code, period="week")
    except Exception:
        weekly_source = pd.DataFrame()
    try:
        monthly_source = get_period_klines(code, period="month")
    except Exception:
        monthly_source = pd.DataFrame()
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
    indicators_ok = indicator_ready(latest)
    kline_date = str(latest.get("date", ""))
    expected_latest = get_latest_closed_trading_date()
    expected_latest_str = expected_latest.isoformat() if expected_latest else None
    freshness_ok = (
        not expected_latest_str
        or kline_date == expected_latest_str
    )
    kline_close = safe_float(latest.get("close"))
    close = kline_close
    scale_guard = price_scale_guard(position, kline_close)
    ma5 = safe_float(latest.get("ma5"))
    ma20 = safe_float(latest.get("ma20"))
    ma60 = safe_float(latest.get("ma60"))
    rsi = safe_float(latest.get("rsi14"), 50)
    macd = safe_float(latest.get("macd"))
    macd_signal = safe_float(latest.get("macd_signal"))
    macd_hist = safe_float(latest.get("macd_hist"))
    prev_macd_hist = safe_float(indicators.iloc[-2].get("macd_hist")) if len(indicators) > 1 else 0
    vol60 = safe_float(latest.get("volatility_60d"))
    vol_tier = volatility_tier(vol60)
    drawdown = abs(safe_float(latest.get("drawdown")))
    ret5 = safe_float(latest.get("ret_5d"))
    ret20 = safe_float(latest.get("ret_20d"))
    ret60 = safe_float(latest.get("ret_60d"))
    atr14 = safe_float(latest.get("atr14"))
    boll_mid = safe_float(latest.get("boll_mid"))
    boll_upper = safe_float(latest.get("boll_upper"))
    boll_lower = safe_float(latest.get("boll_lower"))
    boll_position = safe_float(latest_week.get("boll_position"), 0.5)
    risk_tier = meta.get(code, {}).get("risk_tier", "")
    price_structure = price_structure_analysis(indicators, latest)
    personality = stock_personality_profile(
        code,
        size_tier,
        risk_tier,
        vol_tier,
        plates,
        ret20,
        ret60,
        rsi,
        price_structure,
        daily_short_volume,
        short_interest,
    )
    rsi_hot_threshold = safe_float(personality.get("rsi_hot_threshold"), 76)

    trend_score = 50
    reasons = []
    if not freshness_ok:
        reasons.append(f"K线数据过期: 最新K线 {kline_date}, 应为 {expected_latest_str}")
    if not scale_guard.get("ok"):
        reasons.append(scale_guard.get("reason"))
    if not indicators_ok:
        reasons.append("MACD/均线/波动率等核心指标不足，暂不生成买卖触发价")
    if close > ma5 > 0:
        trend_score += 5
        reasons.append("日K收盘价站上5日均线")
    elif close < ma5 and ma5 > 0:
        trend_score -= 5
        reasons.append("日K收盘价低于5日均线")
    if close > ma20 > 0:
        trend_score += 10
        reasons.append("日K收盘价站上20日均线")
    if ma20 > ma60 > 0:
        trend_score += 12
        reasons.append("20日均线高于60日均线")
    if close < ma60 and ma60 > 0:
        trend_score -= 15
        reasons.append("日K收盘价仍低于60日均线")
    elif close > ma60 > 0:
        reasons.append("日K收盘价高于60日均线")
    if indicators_ok and macd > macd_signal and macd_hist > 0:
        trend_score += 8
        reasons.append("MACD位于信号线上方，短中期动能偏正")
    elif indicators_ok and macd < macd_signal and macd_hist < 0:
        trend_score -= 10
        reasons.append("MACD位于信号线下方，动能仍偏弱")
    macd_improving = indicators_ok and macd_hist > prev_macd_hist
    macd_bullish = indicators_ok and macd > macd_signal and macd_hist > 0
    macd_bearish = indicators_ok and macd < macd_signal and macd_hist < 0
    trend_score += max(-18, min(18, safe_float(price_structure.get("score")) * 0.45))
    reasons.extend(price_structure.get("points", [])[:3])

    momentum_score = 50 + max(-25, min(25, ret20 * 100)) + max(-15, min(15, ret60 * 50))
    if 45 <= rsi <= 68:
        momentum_score += 8
        reasons.append("RSI处在相对健康区间")
    elif rsi > rsi_hot_threshold:
        momentum_score -= 10
        reasons.append(f"RSI高于该股票性格阈值({rsi_hot_threshold:.0f})，追高风险上升")
    elif rsi < 35:
        momentum_score -= 8
        reasons.append("RSI偏弱，趋势仍需确认")

    volatility_risk = min(100, vol60 * 100)
    drawdown_risk = min(100, drawdown * 160)
    concentration_risk = min(100, weight * 250)
    speculative_addon = 15 if risk_tier == "speculative" else 0
    size_addon = 8 if size_tier == "small_cap" else 0
    volatility_addon = 10 if vol_tier == "extreme" else 5 if vol_tier == "high" else 0
    personality_addon = safe_float(personality.get("trim_bias"), 0) if personality.get("speculative") else 0
    valuation_addon, valuation_reasons = valuation_risk_adjustment(valuation)
    financial_addon, financial_reasons = financial_risk_adjustment(financials)
    earnings_addon, earnings_reasons = earnings_risk_adjustment(earnings)
    efficiency_addon, efficiency_reasons = operational_efficiency_risk_adjustment(operational_efficiency)
    capital_addon, capital_reasons = capital_risk_adjustment(capital_flow, capital_distribution)
    short_addon, short_reasons = short_risk_adjustment(daily_short_volume, short_interest)
    shareholders_addon, shareholders_reasons = shareholders_risk_adjustment(
        shareholders_overview,
        shareholders_changes,
    )
    insider_addon, insider_reasons = insider_risk_adjustment(insider_trades, insider_holders)
    risk_score = (
        volatility_risk * weights["volatility"]
        + drawdown_risk * weights["drawdown"]
        + concentration_risk * weights["position_weight"]
        + speculative_addon
        + size_addon
        + volatility_addon
        + personality_addon
        + valuation_addon
        + financial_addon
        + earnings_addon
        + efficiency_addon
        + capital_addon
        + short_addon
        + shareholders_addon
        + insider_addon
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
    pl_ratio = safe_float(position.get("pl_ratio"))
    unrealized_pl = safe_float(position.get("unrealized_pl"))
    confirmed = indicators_ok and freshness_ok
    if not freshness_ok:
        action = "watch"
        suggestion = "K线数据过期，禁止生成交易建议；请先同步最近一个已收盘交易日的日K。"
        confirmed = False
    elif not scale_guard.get("ok"):
        action = "watch"
        suggestion = "价格口径不一致，先观察并刷新不复权日K后再生成交易计划。"
        confirmed = False
    elif not indicators_ok:
        action = "watch"
        suggestion = "核心技术指标不足，先观察，不生成买卖触发价。"
        confirmed = False
    elif risk_score >= 70 and weight >= 0.15 and (macd_bearish or rsi > rsi_hot_threshold - 4 or pl_ratio > 0.20):
        action = "trim"
        suggestion = "风险和仓位都偏高，且动能/获利状态支持分批降低敞口。"
        confirmed = True
    elif pl_ratio >= 0.25 and risk_score >= 58 and (macd_bearish or rsi > rsi_hot_threshold - 6):
        action = "trim"
        suggestion = "已有较明显浮盈且风险不低，可考虑到目标价后分批止盈。"
        confirmed = True
    elif pl_ratio <= -0.15 and technical_score >= 65 and risk_score < 60 and weight < 0.20 and macd_bullish and price_structure.get("status") in ("constructive", "improving"):
        action = "add_candidate"
        suggestion = "持仓浮亏但裸K结构和动能同步修复，可只在触发价附近小比例补仓，避免一次性摊平。"
        confirmed = True
    elif technical_score >= 68 and risk_score < 55 and weight < 0.20 and macd_bullish and price_structure.get("status") in ("constructive", "improving"):
        action = "add_candidate"
        suggestion = "裸K结构、动能和风险匹配度较好，可列入加仓观察，不建议一次性重仓。"
        confirmed = True
    elif technical_score >= 58 and risk_score < 70 and macd_improving:
        action = "hold"
        suggestion = "趋势尚可，当前以持有/观望为主。"
        confirmed = False
    elif technical_score < 45 and macd_bearish:
        action = "reduce_or_watch"
        suggestion = "技术面偏弱，若反弹无量或跌破关键均线，应考虑降低仓位。"
        confirmed = True
    else:
        action = "watch"
        suggestion = "技术指标还没有形成足够确认，暂时观察，不给买卖触发价。"
        confirmed = False

    if unrealized_pl > 0 and risk_score >= 60:
        reasons.append("已有浮盈且风险分偏高，适合预设分批止盈计划")
    if size_tier == "small_cap":
        reasons.append("小盘/投机属性较强，更适合分批处理而不是一次性加仓")
    if vol_tier in ("high", "extreme"):
        reasons.append("历史K线显示波动率偏高，仓位上限应低于普通大盘股")
    reasons.extend(valuation_reasons)
    reasons.extend(financial_reasons)
    reasons.extend(earnings_reasons)
    reasons.extend(efficiency_reasons)
    reasons.extend(capital_reasons)
    reasons.extend(short_reasons)
    reasons.extend(shareholders_reasons)
    reasons.extend(insider_reasons)
    levels = {
        "ma5": ma5,
        "ma20": ma20,
        "ma60": ma60,
        "atr14": atr14,
        "boll_mid": boll_mid,
        "boll_upper": boll_upper,
        "boll_lower": boll_lower,
    }
    trade_plan = position_trade_plan(position, action, risk_score, technical_score, weight, vol_tier, close, daily_frame, levels=levels, confirmed=confirmed, personality=personality)
    analysis_points = make_analysis_points(
        price_structure=price_structure,
        personality=personality,
        close=close,
        ma5=ma5,
        ma20=ma20,
        ma60=ma60,
        rsi=rsi,
        macd=macd,
        macd_signal=macd_signal,
        macd_hist=macd_hist,
        prev_macd_hist=prev_macd_hist,
        vol60=vol60,
        ret20=ret20,
        ret60=ret60,
        atr14=atr14,
        boll_mid=boll_mid,
        boll_upper=boll_upper,
        boll_lower=boll_lower,
        capital_flow=capital_flow,
        capital_distribution=capital_distribution,
        daily_short_volume=daily_short_volume,
        short_interest=short_interest,
        valuation=valuation,
        shareholders_changes=shareholders_changes,
        shareholders_overview=shareholders_overview,
        insider_trades=insider_trades,
        insider_holders=insider_holders,
        financials=financials,
        earnings=earnings,
        operational_efficiency=operational_efficiency,
    )

    return {
        "code": code,
        "name": position.get("name", ""),
        "sector": sector,
        "theme": meta.get(code, {}).get("theme", []) + plate_names(plates)[:5],
        "profile": {
            "risk_tier": risk_tier or "normal",
            "size_tier": size_tier,
            "volatility_tier": vol_tier,
            "personality": personality,
            "plates": plates,
            "valuation": valuation,
            "financials": financial_summary(financials),
            "earnings": earnings_summary(earnings),
            "company_profile": company_profile_summary(company_profile),
            "operational_efficiency": operational_efficiency_summary(operational_efficiency),
            "capital_flow": capital_flow_summary(capital_flow),
            "capital_distribution": capital_distribution_summary(capital_distribution),
            "daily_short_volume": daily_short_volume_summary(daily_short_volume),
            "short_interest": short_interest_summary(short_interest),
            "shareholders_overview": shareholders_overview_summary(shareholders_overview),
            "shareholders_changes": shareholders_changes_summary(shareholders_changes),
            "insider_trades": insider_trades_summary(insider_trades),
            "insider_holders": insider_holders_summary(insider_holders),
        },
        "weight": round(weight, 4),
        "qty": safe_float(position.get("qty")),
        "cost_price": safe_float(position.get("cost_price")),
        "market_val": market_val,
        "close": close,
        "kline_date": kline_date,
        "kline_close": kline_close,
        "price_source": "kline",
        "data_quality": {
            "ok": scale_guard.get("ok") and indicators_ok and freshness_ok,
            "price_scale_ok": scale_guard.get("ok"),
            "indicator_ready": indicators_ok,
            "freshness_ok": freshness_ok,
            "expected_latest_trading_date": expected_latest_str,
            "latest_kline_date": kline_date,
            "position_price": scale_guard.get("position_price"),
            "price_scale_ratio": scale_guard.get("ratio"),
            "reason": scale_guard.get("reason"),
            "kline_autype": "NONE",
        },
        "realized_pl": safe_float(position.get("realized_pl")),
        "unrealized_pl": safe_float(position.get("unrealized_pl")),
        "pl_ratio": safe_float(position.get("pl_ratio")),
        "risk_score": risk_score,
        "technical_score": technical_score,
        "score_breakdown": {
            "trend_score": round(trend_score, 2),
            "momentum_score": round(momentum_score, 2),
            "volatility_risk": round(volatility_risk, 2),
            "drawdown_risk": round(drawdown_risk, 2),
            "concentration_risk": round(concentration_risk, 2),
            "personality_addon": round(personality_addon, 2),
            "valuation_addon": round(valuation_addon, 2),
            "financial_addon": round(financial_addon, 2),
            "earnings_addon": round(earnings_addon, 2),
            "efficiency_addon": round(efficiency_addon, 2),
            "capital_addon": round(capital_addon, 2),
            "short_addon": round(short_addon, 2),
            "shareholders_addon": round(shareholders_addon, 2),
            "insider_addon": round(insider_addon, 2),
        },
        "action": action,
        "confirmed": confirmed,
        "trade_plan": trade_plan,
        "suggestion": suggestion,
        "prediction": {
            "expected_volatility_30d": round(vol60 / math.sqrt(252) * math.sqrt(30), 4) if vol60 else 0,
            "trend_5d": round(ret5, 4),
            "trend_20d": round(ret20, 4),
            "trend_60d": round(ret60, 4),
            "drawdown_from_high": round(drawdown, 4),
        },
        "signals": {
            "daily": {
                "ma5": round(ma5, 4),
                "ma20": round(ma20, 4),
                "ma60": round(ma60, 4),
                "rsi14": round(rsi, 2),
                "macd": round(macd, 4),
                "macd_signal": round(macd_signal, 4),
                "macd_hist": round(macd_hist, 4),
                "atr14": round(atr14, 4),
                "boll_mid": round(boll_mid, 4),
                "boll_upper": round(boll_upper, 4),
                "boll_lower": round(boll_lower, 4),
                "volatility_60d": round(vol60, 4),
                "volatility_tier": vol_tier,
                "ret_5d": round(ret5, 4),
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
        "analysis_points": analysis_points,
        "price_structure": price_structure,
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
        try:
            frame = get_daily_klines(code)
        except Exception:
            continue
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


def portfolio_rating(score):
    if score >= 80:
        return {"grade": "good", "label": "优秀", "description": "结构健康，可以按计划持有和观察机会"}
    if score >= 65:
        return {"grade": "healthy", "label": "良好", "description": "整体可接受，但仍需要控制新增仓位"}
    if score >= 50:
        return {"grade": "watch", "label": "观察", "description": "风险和集中度开始影响组合质量"}
    if score >= 35:
        return {"grade": "risk", "label": "偏高风险", "description": "应优先降低高风险或过度集中的仓位"}
    return {"grade": "bad", "label": "危险", "description": "组合承压明显，先考虑防守和现金流"}


def portfolio_score_summary(reports, portfolio_risk, exposure):
    total_value = sum(item.get("market_val", 0) for item in reports)
    unrealized_pl = sum(item.get("unrealized_pl", 0) for item in reports)
    realized_pl = sum(item.get("realized_pl", 0) for item in reports)
    cost_basis = sum(
        max(0, item.get("market_val", 0) - item.get("unrealized_pl", 0))
        for item in reports
    )
    total_pl = unrealized_pl + realized_pl
    pl_ratio = total_pl / cost_basis if cost_basis > 0 else 0
    concentration_penalty = max(exposure.values(), default=0) * 20
    high_risk_penalty = sum(item.get("weight", 0) for item in reports if item.get("risk_score", 0) >= 70) * 25
    profit_bonus = max(-10, min(10, pl_ratio * 40))
    score = 100 - portfolio_risk * 0.45 - concentration_penalty - high_risk_penalty + profit_bonus
    score = round(max(0, min(100, score)), 1)
    rating = portfolio_rating(score)
    return {
        "score": score,
        "rating": rating.get("grade"),
        "rating_label": rating.get("label"),
        "rating_description": rating.get("description"),
        "ranges": [
            {"min": 80, "max": 100, "rating": "good", "label": "优秀"},
            {"min": 65, "max": 79, "rating": "healthy", "label": "良好"},
            {"min": 50, "max": 64, "rating": "watch", "label": "观察"},
            {"min": 35, "max": 49, "rating": "risk", "label": "偏高风险"},
            {"min": 0, "max": 34, "rating": "bad", "label": "危险"},
        ],
        "pnl": {
            "unrealized_pl": round(unrealized_pl, 2),
            "realized_pl": round(realized_pl, 2),
            "total_pl": round(total_pl, 2),
            "pl_ratio": round(pl_ratio, 4),
        },
    }


def build_position_alerts(reports, updated_at):
    acks = set(load_alert_acks().get("acknowledged_ids", []))
    alerts = []
    for item in reports:
        trade_plan = item.get("trade_plan", {})
        alert_type = trade_plan.get("alert_type")
        if alert_type not in ("buy", "sell"):
            continue
        if alert_type == "sell" and trade_plan.get("sell_percent", 0) <= 0:
            continue
        if alert_type == "buy" and trade_plan.get("buy_percent", 0) <= 0:
            continue
        alert_id = f"position:{item.get('code')}:{item.get('action')}:{updated_at[:10]}"
        alerts.append({
            "id": alert_id,
            "source": "position",
            "code": item.get("code"),
            "name": item.get("name"),
            "alert_type": alert_type,
            "signal": item.get("action"),
            "created_at": updated_at,
            "price": item.get("close"),
            "suggestion": item.get("suggestion"),
            "reasons": item.get("reasons", [])[:5],
            "trade_plan": trade_plan,
            "triggered": False,
            "technical_score": item.get("technical_score"),
            "risk_score": item.get("risk_score"),
            "unrealized_pl": item.get("unrealized_pl"),
            "pl_ratio": item.get("pl_ratio"),
            "acknowledged": alert_id in acks,
        })
    return alerts


def fetch_live_quotes(codes):
    clean_codes = sorted({normalize_symbol(code) for code in codes if normalize_symbol(code)})
    if not clean_codes:
        return {}
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        quote_ctx.subscribe(
            clean_codes,
            [SubType.QUOTE],
            subscribe_push=False,
            extended_time=True,
        )
        ret, data = quote_ctx.get_stock_quote(clean_codes)
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        raise RuntimeError(f"get_stock_quote failed: {data}")
    quotes = {}
    for _, row in data.iterrows():
        code = str(row.get("code", ""))
        price = safe_float(row.get("last_price"))
        if price <= 0:
            price = safe_float(row.get("after_price"))
        if price <= 0:
            price = safe_float(row.get("pre_price"))
        if price <= 0:
            price = safe_float(row.get("prev_close_price"))
        quotes[code] = {
            "code": code,
            "price": price,
            "open": safe_float(row.get("open_price")),
            "high": safe_float(row.get("high_price")),
            "low": safe_float(row.get("low_price")),
            "volume": safe_float(row.get("volume")),
            "turnover": safe_float(row.get("turnover")),
            "data_date": str(row.get("data_date", "")),
            "data_time": str(row.get("data_time", "")),
        }
    return quotes


def frame_tail_records(frame, limit=5):
    if frame.empty:
        return []
    rows = []
    for _, row in frame.tail(limit).iterrows():
        rows.append({
            "date": str(row.get("date", "")),
            "time_key": str(row.get("time_key", "")),
            "open": safe_float(row.get("open"), None),
            "high": safe_float(row.get("high"), None),
            "low": safe_float(row.get("low"), None),
            "close": safe_float(row.get("close"), None),
            "volume": safe_float(row.get("volume"), None),
            "turnover": safe_float(row.get("turnover"), None),
        })
    return rows


def latest_row_date(rows):
    if not rows:
        return None
    return rows[-1].get("date")


def request_raw_kline_tail(code, autype, limit=5, expected_latest=None):
    request_end = expected_latest.isoformat() if expected_latest else None
    request_days = max(30, limit * 5)
    request_start = (
        (expected_latest - timedelta(days=request_days)).isoformat()
        if expected_latest
        else None
    )
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    try:
        ret, data, _ = quote_ctx.request_history_kline(
            code,
            start=request_start,
            end=request_end,
            ktype=KLType.K_DAY,
            autype=autype,
            max_count=max(50, limit * 5),
        )
    finally:
        quote_ctx.close()

    if ret != RET_OK:
        return {
            "ok": False,
            "error": str(data),
            "request_start": request_start,
            "request_end": request_end,
            "rows": [],
        }
    frame = data.copy()
    if "time_key" in frame.columns:
        frame["date"] = pd.to_datetime(frame["time_key"]).dt.date.astype(str)
    return {
        "ok": True,
        "request_start": request_start,
        "request_end": request_end,
        "raw_rows": len(frame),
        "rows": frame_tail_records(frame, limit=limit),
    }


def get_raw_kline_debug(symbols=None, limit=5):
    if symbols:
        codes = [normalize_symbol(symbol) for symbol in symbols.split(",") if symbol.strip()]
        positions = [{"code": code, "name": code} for code in codes]
    else:
        positions_result = get_positions()
        if not positions_result.get("ok"):
            return positions_result
        positions = positions_result.get("positions", [])
        codes = [position.get("code") for position in positions if position.get("code")]

    try:
        quotes = fetch_live_quotes(codes)
    except Exception as exc:
        quotes = {}
        quote_error = str(exc)
    else:
        quote_error = None

    autypes = [
        ("NONE", AuType.NONE),
        ("QFQ", AuType.QFQ),
        ("HFQ", AuType.HFQ),
    ]
    expected_latest = get_latest_closed_trading_date()
    expected_latest_str = expected_latest.isoformat() if expected_latest else None
    results = []
    for position in positions:
        code = position.get("code")
        if not code:
            continue
        variants = {
            name: request_raw_kline_tail(code, autype, limit=limit, expected_latest=expected_latest)
            for name, autype in autypes
        }
        for payload in variants.values():
            latest_date = latest_row_date(payload.get("rows", []))
            payload["latest_date"] = latest_date
            payload["expected_latest_trading_date"] = expected_latest_str
            payload["is_latest_expected"] = latest_date == expected_latest_str if latest_date and expected_latest_str else None
        results.append({
            "code": code,
            "name": position.get("name"),
            "quote": quotes.get(code),
            "quote_error": quote_error,
            "kline_variants": variants,
        })
    return {
        "ok": True,
        "count": len(results),
        "limit": limit,
        "expected_latest_trading_date": expected_latest_str,
        "positions": results,
    }


def price_triggered(price, trigger_price, condition):
    if price <= 0 or not trigger_price:
        return False
    if condition == "price_at_or_above":
        return price >= trigger_price
    if condition == "price_at_or_below":
        return price <= trigger_price
    return False


def monitor_advisor_price_alerts():
    report = load_latest_report()
    if not report.get("ok"):
        return {"ok": False, "error": "advisor report not generated yet"}

    candidates = []
    for item in report.get("positions", []):
        trade_plan = item.get("trade_plan", {})
        if not trade_plan.get("trigger_price") or not trade_plan.get("trigger_condition"):
            continue
        candidates.append(item)
    if not candidates:
        return {"ok": True, "created": 0, "alerts": []}

    quotes = fetch_live_quotes([item.get("code") for item in candidates])
    payload = load_trigger_alerts()
    alerts = payload.setdefault("alerts", [])
    existing_ids = {alert.get("id") for alert in alerts}
    acked_ids = set(load_alert_acks().get("acknowledged_ids", []))
    created = []
    now = utc_now_iso()

    for item in candidates:
        code = item.get("code")
        quote = quotes.get(code, {})
        price = safe_float(quote.get("price"))
        trade_plan = item.get("trade_plan", {})
        trigger_price = safe_float(trade_plan.get("trigger_price"))
        condition = trade_plan.get("trigger_condition")
        if not price_triggered(price, trigger_price, condition):
            continue
        alert_id = f"trigger:{code}:{item.get('action')}:{now[:10]}"
        if alert_id in existing_ids or alert_id in acked_ids:
            continue
        alert = {
            "id": alert_id,
            "source": "price_trigger",
            "code": code,
            "name": item.get("name"),
            "alert_type": trade_plan.get("alert_type"),
            "signal": item.get("action"),
            "created_at": now,
            "price": price,
            "trigger_price": trigger_price,
            "trigger_condition": condition,
            "quote_time": f"{quote.get('data_date', '')} {quote.get('data_time', '')}".strip(),
            "suggestion": item.get("suggestion"),
            "reasons": item.get("reasons", [])[:5],
            "trade_plan": trade_plan,
            "technical_score": item.get("technical_score"),
            "risk_score": item.get("risk_score"),
            "unrealized_pl": item.get("unrealized_pl"),
            "pl_ratio": item.get("pl_ratio"),
            "acknowledged": False,
        }
        alerts.append(alert)
        created.append(alert)
        existing_ids.add(alert_id)

    if created:
        payload["alerts"] = alerts[-200:]
        save_trigger_alerts(payload)
    return {
        "ok": True,
        "created": len(created),
        "alerts": created,
    }


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
    earnings_result = sync_earnings_moves(codes, force=force)
    company_profile_result = sync_company_profiles(codes, force=force)
    operational_efficiency_result = sync_operational_efficiency(codes, force=force)
    capital_flow_result = sync_capital_flows(codes, force=force)
    capital_distribution_result = sync_capital_distributions(codes, force=force)
    daily_short_volume_result = sync_daily_short_volumes(codes, force=force)
    short_interest_result = sync_short_interests(codes, force=force)
    shareholders_overview_result = sync_shareholders_overviews(codes, force=force)
    shareholders_changes_result = sync_shareholders_changes(codes, force=force)
    insider_trades_result = sync_insider_trades(codes, force=force)
    insider_holders_result = sync_insider_holders(codes, force=force)
    return {
        "ok": (
            plate_result.get("ok")
            and valuation_result.get("ok")
            and financial_result.get("ok")
            and earnings_result.get("ok")
            and company_profile_result.get("ok")
            and operational_efficiency_result.get("ok")
            and capital_flow_result.get("ok")
            and capital_distribution_result.get("ok")
            and daily_short_volume_result.get("ok")
            and short_interest_result.get("ok")
            and shareholders_overview_result.get("ok")
            and shareholders_changes_result.get("ok")
            and insider_trades_result.get("ok")
            and insider_holders_result.get("ok")
        ),
        "count": (
            plate_result.get("count", 0)
            + valuation_result.get("count", 0)
            + financial_result.get("count", 0)
            + earnings_result.get("count", 0)
            + company_profile_result.get("count", 0)
            + operational_efficiency_result.get("count", 0)
            + capital_flow_result.get("count", 0)
            + capital_distribution_result.get("count", 0)
            + daily_short_volume_result.get("count", 0)
            + short_interest_result.get("count", 0)
            + shareholders_overview_result.get("count", 0)
            + shareholders_changes_result.get("count", 0)
            + insider_trades_result.get("count", 0)
            + insider_holders_result.get("count", 0)
        ),
        "plates": plate_result,
        "valuations": valuation_result,
        "financials": financial_result,
        "earnings": earnings_result,
        "company_profiles": company_profile_result,
        "operational_efficiency": operational_efficiency_result,
        "capital_flows": capital_flow_result,
        "capital_distributions": capital_distribution_result,
        "daily_short_volumes": daily_short_volume_result,
        "short_interests": short_interest_result,
        "shareholders_overviews": shareholders_overview_result,
        "shareholders_changes": shareholders_changes_result,
        "insider_trades": insider_trades_result,
        "insider_holders": insider_holders_result,
    }


def get_positions_indicator_debug(force_sync=False):
    positions_result = get_positions()
    if not positions_result.get("ok"):
        return positions_result

    results = []
    for position in positions_result.get("positions", []):
        code = position.get("code")
        if not code:
            continue
        if force_sync:
            try:
                sync_daily_klines(code, force=True)
            except Exception as exc:
                results.append({
                    "ok": False,
                    "code": code,
                    "name": position.get("name"),
                    "error": f"sync_daily_klines failed: {exc}",
                })
                continue

        try:
            frame = get_daily_klines(code)
        except Exception as exc:
            results.append({
                "ok": False,
                "code": code,
                "name": position.get("name"),
                "error": f"get_daily_klines failed: {exc}",
            })
            continue

        if frame.empty:
            results.append({
                "ok": False,
                "code": code,
                "name": position.get("name"),
                "error": "daily kline cache is empty",
            })
            continue

        indicators = add_indicators(frame)
        latest = indicators.iloc[-1]
        previous = indicators.iloc[-2] if len(indicators) > 1 else latest
        qty = safe_float(position.get("qty"))
        market_val = safe_float(position.get("market_val"))
        position_price = market_val / qty if qty > 0 else 0
        kline_close = safe_float(latest.get("close"))
        scale_guard = price_scale_guard(position, kline_close)

        results.append({
            "ok": True,
            "code": code,
            "name": position.get("name"),
            "rows": len(frame),
            "expected_kline_autype": "NONE",
            "position": {
                "qty": qty,
                "market_val": market_val,
                "cost_price": safe_float(position.get("cost_price")),
                "position_price": position_price,
                "unrealized_pl": safe_float(position.get("unrealized_pl")),
                "pl_ratio": safe_float(position.get("pl_ratio")),
            },
            "data_quality": {
                "price_scale_ok": scale_guard.get("ok"),
                "price_scale_ratio": scale_guard.get("ratio"),
                "reason": scale_guard.get("reason"),
            },
            "latest_kline": {
                "date": str(latest.get("date", "")),
                "open": safe_float(latest.get("open")),
                "high": safe_float(latest.get("high")),
                "low": safe_float(latest.get("low")),
                "close": kline_close,
                "volume": safe_float(latest.get("volume")),
                "turnover": safe_float(latest.get("turnover")),
            },
            "previous_kline": {
                "date": str(previous.get("date", "")),
                "close": safe_float(previous.get("close")),
                "macd_hist": safe_float(previous.get("macd_hist")),
            },
            "indicators": {
                "ma5": safe_float(latest.get("ma5"), None),
                "ma20": safe_float(latest.get("ma20"), None),
                "ma60": safe_float(latest.get("ma60"), None),
                "ma120": safe_float(latest.get("ma120"), None),
                "rsi14": safe_float(latest.get("rsi14"), None),
                "macd": safe_float(latest.get("macd"), None),
                "macd_signal": safe_float(latest.get("macd_signal"), None),
                "macd_hist": safe_float(latest.get("macd_hist"), None),
                "macd_hist_previous": safe_float(previous.get("macd_hist"), None),
                "atr14": safe_float(latest.get("atr14"), None),
                "boll_mid": safe_float(latest.get("boll_mid"), None),
                "boll_upper": safe_float(latest.get("boll_upper"), None),
                "boll_lower": safe_float(latest.get("boll_lower"), None),
                "boll_position": safe_float(latest.get("boll_position"), None),
                "ret_1d": safe_float(latest.get("ret_1d"), None),
                "ret_20d": safe_float(latest.get("ret_20d"), None),
                "ret_60d": safe_float(latest.get("ret_60d"), None),
                "volatility_20d": safe_float(latest.get("volatility_20d"), None),
                "volatility_60d": safe_float(latest.get("volatility_60d"), None),
                "drawdown": safe_float(latest.get("drawdown"), None),
            },
            "checks": {
                "close_above_ma5": kline_close > safe_float(latest.get("ma5")) > 0,
                "close_above_ma20": kline_close > safe_float(latest.get("ma20")) > 0,
                "close_above_ma60": kline_close > safe_float(latest.get("ma60")) > 0,
                "ma5_gt_ma20": safe_float(latest.get("ma5")) > safe_float(latest.get("ma20")) > 0,
                "ma20_gt_ma60": safe_float(latest.get("ma20")) > safe_float(latest.get("ma60")) > 0,
                "macd_above_signal": safe_float(latest.get("macd")) > safe_float(latest.get("macd_signal")),
                "macd_hist_improving": safe_float(latest.get("macd_hist")) > safe_float(previous.get("macd_hist")),
            },
        })

    return {
        "ok": True,
        "count": len(results),
        "positions": results,
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
    earnings = get_earnings_moves(codes)
    company_profiles = get_company_profiles(codes)
    operational_efficiency = get_operational_efficiency(codes)
    capital_flows = get_capital_flows(codes)
    capital_distributions = get_capital_distributions(codes)
    daily_short_volumes = get_daily_short_volumes(codes)
    short_interests = get_short_interests(codes)
    shareholders_overviews = get_shareholders_overviews(codes)
    shareholders_changes = get_shareholders_changes(codes)
    insider_trades = get_insider_trades(codes)
    insider_holders = get_insider_holders(codes)
    if force_sync:
        for position in positions:
            code = position.get("code")
            if code:
                sync_all_period_klines(code, force=True)
        owner_plates = get_owner_plates(codes, force=True)
        valuations = get_valuations(codes, force=True)
        financials = get_financials(codes, force=True)
        earnings = get_earnings_moves(codes, force=True)
        company_profiles = get_company_profiles(codes, force=True)
        operational_efficiency = get_operational_efficiency(codes, force=True)
        capital_flows = get_capital_flows(codes, force=True)
        capital_distributions = get_capital_distributions(codes, force=True)
        daily_short_volumes = get_daily_short_volumes(codes, force=True)
        short_interests = get_short_interests(codes, force=True)
        shareholders_overviews = get_shareholders_overviews(codes, force=True)
        shareholders_changes = get_shareholders_changes(codes, force=True)
        insider_trades = get_insider_trades(codes, force=True)
        insider_holders = get_insider_holders(codes, force=True)

    portfolio_value = sum(safe_float(item.get("market_val")) for item in positions)
    reports = []
    for position in positions:
        code = position.get("code")
        if not code:
            continue
        try:
            frame = get_daily_klines(code)
        except Exception:
            frame = pd.DataFrame()
        reports.append(score_position(
            position,
            frame,
            portfolio_value,
            state["weights"],
            meta,
            plates=owner_plates.get(code, []),
            valuation=valuations.get(code),
            financials=financials.get(code),
            earnings=earnings.get(code),
            company_profile=company_profiles.get(code),
            operational_efficiency=operational_efficiency.get(code),
            capital_flow=capital_flows.get(code),
            capital_distribution=capital_distributions.get(code),
            daily_short_volume=daily_short_volumes.get(code),
            short_interest=short_interests.get(code),
            shareholders_overview=shareholders_overviews.get(code),
            shareholders_changes=shareholders_changes.get(code),
            insider_trades=insider_trades.get(code),
            insider_holders=insider_holders.get(code),
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

    updated_at = utc_now_iso()
    score_summary = portfolio_score_summary(reports, portfolio_risk, exposure)
    position_alerts = build_position_alerts(reports, updated_at)
    report = {
        "ok": True,
        "updated_at": updated_at,
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
            "score": score_summary["score"],
            "rating": score_summary["rating"],
            "rating_label": score_summary["rating_label"],
            "rating_description": score_summary["rating_description"],
            "score_ranges": score_summary["ranges"],
            "pnl": score_summary["pnl"],
        },
        "alerts": position_alerts,
        "positions": sorted(reports, key=lambda item: item.get("risk_score", 0), reverse=True),
    }
    write_json(ADVISOR_REPORT_FILE, report)
    return report


def load_latest_report():
    return read_json(ADVISOR_REPORT_FILE, {"ok": False, "error": "advisor report not generated yet"})


def compact_position_advice(position):
    return {
        "code": position.get("code"),
        "name": position.get("name"),
        "sector": position.get("sector"),
        "weight": position.get("weight"),
        "qty": position.get("qty"),
        "cost_price": position.get("cost_price"),
        "market_val": position.get("market_val"),
        "close": position.get("close"),
        "kline_date": position.get("kline_date"),
        "kline_close": position.get("kline_close"),
        "price_source": position.get("price_source"),
        "realized_pl": position.get("realized_pl"),
        "unrealized_pl": position.get("unrealized_pl"),
        "pl_ratio": position.get("pl_ratio"),
        "risk_score": position.get("risk_score"),
        "technical_score": position.get("technical_score"),
        "score_breakdown": position.get("score_breakdown", {}),
        "action": position.get("action"),
        "confirmed": position.get("confirmed"),
        "trade_plan": position.get("trade_plan", {}),
        "suggestion": position.get("suggestion"),
        "reasons": position.get("reasons", []),
        "analysis_points": position.get("analysis_points", []),
        "price_structure": position.get("price_structure", {}),
        "prediction": position.get("prediction", {}),
        "signals": position.get("signals", {}),
        "profile": {
            "risk_tier": position.get("profile", {}).get("risk_tier"),
            "size_tier": position.get("profile", {}).get("size_tier"),
            "volatility_tier": position.get("profile", {}).get("volatility_tier"),
            "personality": position.get("profile", {}).get("personality"),
            "valuation": position.get("profile", {}).get("valuation"),
            "financials": position.get("profile", {}).get("financials"),
            "earnings": position.get("profile", {}).get("earnings"),
            "operational_efficiency": position.get("profile", {}).get("operational_efficiency"),
            "capital_flow": position.get("profile", {}).get("capital_flow"),
            "capital_distribution": position.get("profile", {}).get("capital_distribution"),
            "daily_short_volume": position.get("profile", {}).get("daily_short_volume"),
            "short_interest": position.get("profile", {}).get("short_interest"),
            "shareholders_overview": position.get("profile", {}).get("shareholders_overview"),
            "shareholders_changes": position.get("profile", {}).get("shareholders_changes"),
            "insider_trades": position.get("profile", {}).get("insider_trades"),
            "insider_holders": position.get("profile", {}).get("insider_holders"),
        },
    }


def compact_report(report):
    if not report.get("ok"):
        return report
    portfolio = report.get("portfolio", {})
    portfolio_suggestion = "组合风险正常，继续按计划观察。"
    if portfolio.get("risk_score", 0) >= 70:
        portfolio_suggestion = "组合风险偏高，优先降低集中仓位和高波动标的。"
    elif portfolio.get("risk_score", 0) >= 45:
        portfolio_suggestion = "组合有一定集中度或波动压力，适合控制新增仓位。"
    return {
        "ok": True,
        "updated_at": report.get("updated_at"),
        "portfolio": {
            "market_value": portfolio.get("market_value"),
            "risk_score": portfolio.get("risk_score"),
            "score": portfolio.get("score"),
            "rating": portfolio.get("rating"),
            "rating_label": portfolio.get("rating_label"),
            "rating_description": portfolio.get("rating_description"),
            "score_ranges": portfolio.get("score_ranges", []),
            "pnl": portfolio.get("pnl", {}),
            "max_position_weight": portfolio.get("max_position_weight"),
            "high_risk_weight": portfolio.get("high_risk_weight"),
            "sector_exposure": portfolio.get("sector_exposure", {}),
            "correlation": portfolio.get("correlation", {}),
            "suggestion": portfolio_suggestion,
            "reasons": portfolio.get("reasons", []),
        },
        "positions": [
            compact_position_advice(item)
            for item in report.get("positions", [])
        ],
        "alerts": [
            item for item in report.get("alerts", [])
            if not item.get("acknowledged")
        ],
    }


def get_advisor_summary(refresh=False):
    report = build_advisor_report(force_sync=False) if refresh else load_latest_report()
    if not report.get("ok"):
        report = build_advisor_report(force_sync=False)
    return compact_report(report)


def get_symbol_advice(code, refresh=False):
    code = normalize_symbol(code)
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


def sync_symbol_profile_set(codes, force=False):
    clean_codes = sorted({normalize_symbol(code) for code in codes if normalize_symbol(code)})
    return {
        "ok": True,
        "codes": clean_codes,
        "owner_plates": sync_owner_plates(clean_codes, force=force),
        "valuations": sync_valuations(clean_codes, force=force),
        "financials": sync_financials(clean_codes, force=force),
        "earnings": sync_earnings_moves(clean_codes, force=force),
        "company_profiles": sync_company_profiles(clean_codes, force=force),
        "operational_efficiency": sync_operational_efficiency(clean_codes, force=force),
        "capital_flows": sync_capital_flows(clean_codes, force=force),
        "capital_distributions": sync_capital_distributions(clean_codes, force=force),
        "daily_short_volumes": sync_daily_short_volumes(clean_codes, force=force),
        "short_interests": sync_short_interests(clean_codes, force=force),
        "shareholders_overviews": sync_shareholders_overviews(clean_codes, force=force),
        "shareholders_changes": sync_shareholders_changes(clean_codes, force=force),
        "insider_trades": sync_insider_trades(clean_codes, force=force),
        "insider_holders": sync_insider_holders(clean_codes, force=force),
    }


def build_candidate_advice(code, force_sync=False):
    code = normalize_symbol(code)
    if not code:
        return {"ok": False, "error": "symbol is required"}

    if force_sync:
        try:
            sync_daily_klines(code, force=True)
        except Exception:
            pass
        try:
            sync_symbol_profile_set([code], force=True)
        except Exception:
            pass

    meta = load_symbol_meta()
    try:
        frame = get_daily_klines(code)
    except Exception:
        frame = pd.DataFrame()

    owner_plates = get_owner_plates([code]).get(code, [])
    fake_position = {
        "code": code,
        "name": code,
        "market_val": 0,
        "unrealized_pl": 0,
        "is_etf": False,
    }
    advice = score_position(
        fake_position,
        frame,
        0,
        load_advisor_state()["weights"],
        meta,
        plates=owner_plates,
        valuation=get_valuations([code]).get(code),
        financials=get_financials([code]).get(code),
        earnings=get_earnings_moves([code]).get(code),
        company_profile=get_company_profiles([code]).get(code),
        operational_efficiency=get_operational_efficiency([code]).get(code),
        capital_flow=get_capital_flows([code]).get(code),
        capital_distribution=get_capital_distributions([code]).get(code),
        daily_short_volume=get_daily_short_volumes([code]).get(code),
        short_interest=get_short_interests([code]).get(code),
        shareholders_overview=get_shareholders_overviews([code]).get(code),
        shareholders_changes=get_shareholders_changes([code]).get(code),
        insider_trades=get_insider_trades([code]).get(code),
        insider_holders=get_insider_holders([code]).get(code),
    )
    action = advice.get("action")
    signal = "watch"
    if action == "add_candidate" and advice.get("technical_score", 0) >= 68 and advice.get("risk_score", 100) < 55:
        signal = "buy_watch"
    elif action in ("trim", "reduce_or_watch"):
        signal = "avoid_or_wait"

    return {
        "ok": True,
        "updated_at": utc_now_iso(),
        "code": code,
        "signal": signal,
        "should_notify": signal == "buy_watch",
        "observation_window_days": 5,
        "advice": advice,
    }


def add_watch_symbol(code, note="", force_sync=False):
    code = normalize_symbol(code)
    if not code:
        return {"ok": False, "error": "symbol is required"}
    payload = load_watchlist()
    symbols = payload.setdefault("symbols", {})
    now = utc_now_iso()
    item = symbols.get(code, {})
    item.setdefault("created_at", now)
    item.setdefault("observations", [])
    item.update({
        "code": code,
        "status": "active",
        "note": note,
        "updated_at": now,
        "observation_window_days": 5,
    })
    symbols[code] = item
    save_watchlist(payload)
    advice = build_candidate_advice(code, force_sync=force_sync)
    if advice.get("should_notify"):
        alert_id = f"{code}:{advice.get('updated_at')}:buy_watch"
        item["last_alert"] = {
            "id": alert_id,
            "code": code,
            "signal": advice.get("signal"),
            "created_at": advice.get("updated_at"),
            "suggestion": advice.get("advice", {}).get("suggestion"),
            "reasons": advice.get("advice", {}).get("reasons", [])[:5],
            "technical_score": advice.get("advice", {}).get("technical_score"),
            "risk_score": advice.get("advice", {}).get("risk_score"),
            "acknowledged": False,
        }
        save_watchlist(payload)
    return {"ok": True, "watch": item, "analysis": advice}


def update_watch_symbol(code, status=None, note=None, delete=False):
    code = normalize_symbol(code)
    payload = load_watchlist()
    symbols = payload.setdefault("symbols", {})
    if code not in symbols:
        return {"ok": False, "error": f"{code} is not in watchlist"}
    if delete:
        removed = symbols.pop(code)
        save_watchlist(payload)
        return {"ok": True, "deleted": True, "watch": removed}
    if status:
        symbols[code]["status"] = status
    if note is not None:
        symbols[code]["note"] = note
    symbols[code]["updated_at"] = utc_now_iso()
    save_watchlist(payload)
    return {"ok": True, "watch": symbols[code]}


def refresh_watchlist(force_sync=False):
    payload = load_watchlist()
    symbols = payload.setdefault("symbols", {})
    active_codes = [
        code for code, item in symbols.items()
        if item.get("status", "active") == "active"
    ]
    analyses = []
    for code in active_codes:
        analysis = build_candidate_advice(code, force_sync=force_sync)
        alert_id = None
        if analysis.get("should_notify"):
            alert_id = f"{code}:{analysis.get('updated_at')}:buy_watch"
        observations = symbols[code].setdefault("observations", [])
        observations.append({
            "recorded_at": analysis.get("updated_at", utc_now_iso()),
            "signal": analysis.get("signal"),
            "should_notify": analysis.get("should_notify", False),
            "alert_id": alert_id,
            "technical_score": analysis.get("advice", {}).get("technical_score"),
            "risk_score": analysis.get("advice", {}).get("risk_score"),
            "action": analysis.get("advice", {}).get("action"),
            "suggestion": analysis.get("advice", {}).get("suggestion"),
            "reasons": analysis.get("advice", {}).get("reasons", [])[:5],
        })
        symbols[code]["observations"] = observations[-30:]
        symbols[code]["last_signal"] = analysis.get("signal")
        symbols[code]["last_analysis_at"] = analysis.get("updated_at")
        if alert_id:
            symbols[code]["last_alert"] = {
                "id": alert_id,
                "code": code,
                "signal": analysis.get("signal"),
                "created_at": analysis.get("updated_at"),
                "suggestion": analysis.get("advice", {}).get("suggestion"),
                "reasons": analysis.get("advice", {}).get("reasons", [])[:5],
                "technical_score": analysis.get("advice", {}).get("technical_score"),
                "risk_score": analysis.get("advice", {}).get("risk_score"),
                "acknowledged": False,
            }
        analyses.append(analysis)
    save_watchlist(payload)
    return {
        "ok": True,
        "updated_at": payload.get("updated_at"),
        "count": len(analyses),
        "watchlist": payload,
        "analyses": analyses,
    }


def get_watch_alerts(include_acknowledged=False):
    payload = load_watchlist()
    acked_ids = set(load_alert_acks().get("acknowledged_ids", []))
    alerts = []
    for code, item in payload.get("symbols", {}).items():
        if item.get("status", "active") != "active":
            continue
        alert = item.get("last_alert")
        if not alert:
            continue
        alert["source"] = "watchlist"
        alert["alert_type"] = "buy"
        if alert.get("acknowledged") and not include_acknowledged:
            continue
        alerts.append(alert)

    trigger_payload = load_trigger_alerts()
    for alert in trigger_payload.get("alerts", []):
        if alert.get("id") in acked_ids:
            alert["acknowledged"] = True
        if alert.get("acknowledged") and not include_acknowledged:
            continue
        alerts.append(alert)

    alerts.sort(key=lambda item: item.get("created_at", ""), reverse=True)
    return {
        "ok": True,
        "updated_at": max(payload.get("updated_at", ""), trigger_payload.get("updated_at", "")),
        "count": len(alerts),
        "alerts": alerts,
    }


def acknowledge_watch_alert(symbol=None, alert_id=None):
    payload = load_watchlist()
    ack_payload = load_alert_acks()
    acked_ids = set(ack_payload.get("acknowledged_ids", []))
    changed = 0
    for code, item in payload.get("symbols", {}).items():
        if symbol and code != normalize_symbol(symbol):
            continue
        alert = item.get("last_alert")
        if not alert:
            continue
        if alert_id and alert.get("id") != alert_id:
            continue
        alert["acknowledged"] = True
        alert["acknowledged_at"] = utc_now_iso()
        changed += 1
    trigger_payload = load_trigger_alerts()
    for alert in trigger_payload.get("alerts", []):
        if symbol and alert.get("code") != normalize_symbol(symbol):
            continue
        if alert_id and alert.get("id") != alert_id:
            continue
        acked_ids.add(alert.get("id"))
        alert["acknowledged"] = True
        alert["acknowledged_at"] = utc_now_iso()
        changed += 1
    if changed:
        save_watchlist(payload)
        save_trigger_alerts(trigger_payload)
        ack_payload["acknowledged_ids"] = sorted(item for item in acked_ids if item)
        save_alert_acks(ack_payload)
    return {
        "ok": True,
        "acknowledged": changed,
    }
