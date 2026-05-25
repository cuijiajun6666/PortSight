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
from config import DATA_DIR
from routes.positions import get_positions


ADVISOR_STATE_FILE = DATA_DIR / "advisor_state.json"
ADVISOR_REPORT_FILE = DATA_DIR / "advisor_report.json"
SYMBOL_META_FILE = DATA_DIR / "advisor_symbol_meta.json"
ADVISOR_WATCHLIST_FILE = DATA_DIR / "advisor_watchlist.json"

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
    reasons.extend(earnings_reasons)
    reasons.extend(efficiency_reasons)
    reasons.extend(capital_reasons)
    reasons.extend(short_reasons)
    reasons.extend(shareholders_reasons)
    reasons.extend(insider_reasons)

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


def compact_position_advice(position):
    return {
        "code": position.get("code"),
        "name": position.get("name"),
        "sector": position.get("sector"),
        "weight": position.get("weight"),
        "market_val": position.get("market_val"),
        "close": position.get("close"),
        "risk_score": position.get("risk_score"),
        "technical_score": position.get("technical_score"),
        "action": position.get("action"),
        "suggestion": position.get("suggestion"),
        "reasons": position.get("reasons", []),
        "prediction": position.get("prediction", {}),
        "signals": position.get("signals", {}),
        "profile": {
            "risk_tier": position.get("profile", {}).get("risk_tier"),
            "size_tier": position.get("profile", {}).get("size_tier"),
            "volatility_tier": position.get("profile", {}).get("volatility_tier"),
            "valuation": position.get("profile", {}).get("valuation"),
            "capital_flow": position.get("profile", {}).get("capital_flow"),
            "short_interest": position.get("profile", {}).get("short_interest"),
            "shareholders_changes": position.get("profile", {}).get("shareholders_changes"),
            "insider_trades": position.get("profile", {}).get("insider_trades"),
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
    alerts = []
    for code, item in payload.get("symbols", {}).items():
        if item.get("status", "active") != "active":
            continue
        alert = item.get("last_alert")
        if not alert:
            continue
        if alert.get("acknowledged") and not include_acknowledged:
            continue
        alerts.append(alert)
    alerts.sort(key=lambda item: item.get("created_at", ""), reverse=True)
    return {
        "ok": True,
        "updated_at": payload.get("updated_at"),
        "count": len(alerts),
        "alerts": alerts,
    }


def acknowledge_watch_alert(symbol=None, alert_id=None):
    payload = load_watchlist()
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
    if changed:
        save_watchlist(payload)
    return {
        "ok": True,
        "acknowledged": changed,
    }
