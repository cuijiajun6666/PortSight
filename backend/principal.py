from datetime import date, timedelta
from moomoo import *
from utils import safe_float

INITIAL_PRINCIPAL_DATES = [
    "2025-12-23",
    "2025-12-26",
    "2025-12-29",
    "2026-01-03",
    "2026-01-05",
    "2026-01-06",
    "2026-01-12",
    "2026-01-13",
    "2026-01-16",
    "2026-02-22",
    "2026-02-23",
    "2026-04-08",
    "2026-04-27"
]

principal_cache = {}
last_checked_date = None
seen_principal_flows = set()


def is_currency_exchange_flow(row):
    cashflow_type = str(row.get("cashflow_type", "")).lower()
    return "货币兑换" in cashflow_type or "currency exchange" in cashflow_type


def is_principal_flow(row):
    cashflow_type = str(row.get("cashflow_type", ""))
    remark = str(row.get("cashflow_remark", ""))

    text = cashflow_type + " " + remark

    include_keywords = [
        "银行转存",
        "银行转出",
        "银行转入",
        "存入资金",
        "提取资金",
        "入金",
        "出金",
        "Deposit",
        "Withdrawal"
    ]

    exclude_keywords = [
        "基金申购",
        "基金赎回",
        "Fund Subscription",
        "Fund Redemption",
        "股票买入",
        "股票卖出",
        "期权",
        "Opt "
    ]

    normalized_text = text.lower()
    if any(k.lower() in normalized_text for k in exclude_keywords):
        return False

    return any(k.lower() in normalized_text for k in include_keywords)


def flow_key(row):
    cashflow_id = str(row.get("cashflow_id", ""))
    if cashflow_id:
        return (cashflow_id,)

    return (
        str(row.get("clearing_date", "")),
        str(row.get("currency", "")),
        str(row.get("cashflow_type", "")),
        str(row.get("cashflow_direction", "")),
        str(row.get("cashflow_amount", "")),
        str(row.get("cashflow_remark", ""))
    )


def apply_new_principal_flows(trd_ctx, start_date, end_date):
    global principal_cache, seen_principal_flows

    new_count = 0
    start = date.fromisoformat(start_date)
    end = date.fromisoformat(end_date)

    current = start
    while current <= end:
        ret, data = trd_ctx.get_acc_cash_flow(
            clearing_date=current.isoformat(),
            trd_env=TrdEnv.REAL,
            acc_id=0,
            acc_index=0,
            cashflow_direction=CashFlowDirection.NONE
        )

        if ret != RET_OK:
            print("本金流水获取失败:", current.isoformat(), data)
        elif not data.empty:
            for _, row in data.iterrows():
                if is_principal_flow(row) or is_currency_exchange_flow(row):
                    key = flow_key(row)
                    if key in seen_principal_flows:
                        continue

                    currency = str(row["currency"])
                    amount = safe_float(row["cashflow_amount"])

                    principal_cache[currency] = principal_cache.get(currency, 0.0) + amount
                    seen_principal_flows.add(key)
                    new_count += 1
                    print(
                        "识别到本金流水:",
                        current.isoformat(),
                        currency,
                        amount,
                        row.get("cashflow_type", ""),
                        row.get("cashflow_direction", ""),
                        row.get("cashflow_remark", "")
                    )

        current += timedelta(days=1)

    if new_count == 0:
        print("没有新增本金流水:", start_date, "到", end_date)

    return new_count


def apply_new_principal_flows_for_dates(trd_ctx, clearing_dates):
    global principal_cache, seen_principal_flows

    new_count = 0

    for clearing_date in sorted(set(clearing_dates)):
        ret, data = trd_ctx.get_acc_cash_flow(
            clearing_date=clearing_date,
            trd_env=TrdEnv.REAL,
            acc_id=0,
            acc_index=0,
            cashflow_direction=CashFlowDirection.NONE
        )

        if ret != RET_OK:
            print("本金流水获取失败:", clearing_date, data)
        elif not data.empty:
            for _, row in data.iterrows():
                if is_principal_flow(row) or is_currency_exchange_flow(row):
                    key = flow_key(row)
                    if key in seen_principal_flows:
                        continue

                    currency = str(row["currency"])
                    amount = safe_float(row["cashflow_amount"])

                    principal_cache[currency] = principal_cache.get(currency, 0.0) + amount
                    seen_principal_flows.add(key)
                    new_count += 1
                    print(
                        "识别到本金流水:",
                        clearing_date,
                        currency,
                        amount,
                        row.get("cashflow_type", ""),
                        row.get("cashflow_direction", ""),
                        row.get("cashflow_remark", "")
                    )

    if new_count == 0:
        print("固定日期没有识别到本金流水:", ", ".join(sorted(set(clearing_dates))))

    return new_count


def calculate_principal(trd_ctx):
    global principal_cache, seen_principal_flows

    principal_cache = {}
    seen_principal_flows = set()
    apply_new_principal_flows_for_dates(trd_ctx, INITIAL_PRINCIPAL_DATES)
    return dict(principal_cache)


def init_principal_cache(trd_ctx):
    global principal_cache, last_checked_date

    principal_cache = calculate_principal(trd_ctx)
    last_checked_date = date.today()

    print("初始本金:", principal_cache)
    return dict(principal_cache)


def update_today_principal(trd_ctx):
    global principal_cache, last_checked_date

    today = date.today()

    if last_checked_date is None:
        return init_principal_cache(trd_ctx)

    start_date = last_checked_date if last_checked_date == today else last_checked_date + timedelta(days=1)
    apply_new_principal_flows(
        trd_ctx,
        start_date=start_date.isoformat(),
        end_date=today.isoformat()
    )
    last_checked_date = today
    return dict(principal_cache)


def get_principal_total(aud_to_usd_rate=None):
    total = safe_float(principal_cache.get("USD", 0))

    aud_principal = safe_float(principal_cache.get("AUD", 0))
    if abs(aud_principal) > 0.01:
        if aud_to_usd_rate is None:
            print("存在未兑换 AUD 本金，但没有 AUD/USD 实时汇率:", aud_principal)
        else:
            total += aud_principal * aud_to_usd_rate

    return total


def get_principal_usd(aud_to_usd_rate=None):
    principal = {"USD": safe_float(principal_cache.get("USD", 0))}

    aud_principal = safe_float(principal_cache.get("AUD", 0))
    if abs(aud_principal) > 0.01 and aud_to_usd_rate is not None:
        principal["AUD"] = aud_principal * aud_to_usd_rate

    return principal
