from fastapi import APIRouter, Query

from moomoo import *

from config import HOST, PORT
from asset_snapshots import get_latest_valid_principal
from principal import (
    update_today_principal,
    get_principal_total,
    get_principal_usd,
    is_principal_flow,
    is_currency_exchange_flow
)

router = APIRouter()


def create_trade_context():
    return OpenSecTradeContext(
        filter_trdmarket=TrdMarket.US,
        host=HOST,
        port=PORT,
        security_firm=SecurityFirm.FUTUAU
    )


def query_account_info(trd_ctx, currency):
    ret, data = trd_ctx.accinfo_query(
        trd_env=TrdEnv.REAL,
        currency=currency
    )

    if ret != RET_OK or data.empty:
        return ret, data, None

    return ret, data, data.iloc[0]


def get_aud_to_usd_rate(usd_row, aud_row):
    usd_total_assets = float(usd_row.get("total_assets", 0))
    aud_total_assets = float(aud_row.get("total_assets", 0)) if aud_row is not None else 0

    if usd_total_assets <= 0 or aud_total_assets <= 0:
        return None

    return usd_total_assets / aud_total_assets


def get_cash_by_currency(row):
    cash_by_currency = {
        "USD": float(row.get("us_cash", 0)),
        "AUD": float(row.get("au_cash", 0))
    }

    return cash_by_currency


def guarded_principal_total(calculated_principal: float):
    fallback_principal = get_latest_valid_principal()
    if fallback_principal is None:
        return calculated_principal, False, None

    if calculated_principal <= 0:
        return fallback_principal, True, fallback_principal

    if calculated_principal < 1000 and fallback_principal >= 1000:
        print(
            "本金计算疑似不完整，使用历史本金兜底:",
            calculated_principal,
            "->",
            fallback_principal
        )
        return fallback_principal, True, fallback_principal

    return calculated_principal, False, fallback_principal

@router.get("/account")
def get_account():
    trd_ctx = create_trade_context()

    # 👉 账户资产
    ret, data, row = query_account_info(trd_ctx, Currency.USD)

    if ret != RET_OK or row is None:
        trd_ctx.close()
        return {"ok": False, "error": str(data)}

    _, _, aud_row = query_account_info(trd_ctx, Currency.AUD)
    aud_to_usd_rate = get_aud_to_usd_rate(row, aud_row)

    total_assets = float(row.get("total_assets", 0))
    cash_by_currency = get_cash_by_currency(row)

    # 👉 本金：启动时全量缓存，之后每次刷新只检查新增入金/出金流水
    principal_dict = update_today_principal(trd_ctx)
    calculated_principal_total = get_principal_total(aud_to_usd_rate)
    principal_total, principal_guarded, fallback_principal = guarded_principal_total(
        calculated_principal_total
    )
    principal_usd = get_principal_usd(aud_to_usd_rate)

    trd_ctx.close()

    return {
        "ok": True,
        "total_assets": total_assets,
        "buying_power": float(row.get("power", 0)),
        "cash": float(row.get("cash", 0)),
        "cash_by_currency": cash_by_currency,
        "market_value": float(row.get("market_val", 0)),
        "principal": principal_usd,
        "principal_total": principal_total,
        "calculated_principal_total": calculated_principal_total,
        "principal_guarded": principal_guarded,
        "fallback_principal": fallback_principal,
        "principal_original": principal_dict,
        "aud_to_usd_rate": aud_to_usd_rate,
        "currency": str(row.get("currency", "USD"))
    }

def fetch_account_snapshot():
    trd_ctx = create_trade_context()

    ret, data, row = query_account_info(trd_ctx, Currency.USD)

    if ret != RET_OK or row is None:
        trd_ctx.close()
        return None

    _, _, aud_row = query_account_info(trd_ctx, Currency.AUD)
    aud_to_usd_rate = get_aud_to_usd_rate(row, aud_row)

    principal_dict = update_today_principal(trd_ctx)
    calculated_principal_total = get_principal_total(aud_to_usd_rate)
    principal_total, principal_guarded, fallback_principal = guarded_principal_total(
        calculated_principal_total
    )
    principal_usd = get_principal_usd(aud_to_usd_rate)

    trd_ctx.close()

    return {
        "total_assets": float(row.get("total_assets")),
        "principal": principal_total,
        "calculated_principal": calculated_principal_total,
        "principal_guarded": principal_guarded,
        "fallback_principal": fallback_principal,
        "principal_by_currency": principal_usd,
        "principal_original": principal_dict,
        "aud_to_usd_rate": aud_to_usd_rate
    }


@router.get("/cash_flow_debug")
@router.get("/cashflow_debug")
@router.get("/cash-flow-debug")
def get_cash_flow_debug(clearing_date: str = Query(...)):
    trd_ctx = create_trade_context()
    ret, data = trd_ctx.get_acc_cash_flow(
        clearing_date=clearing_date,
        trd_env=TrdEnv.REAL,
        acc_id=0,
        acc_index=0,
        cashflow_direction=CashFlowDirection.NONE
    )
    trd_ctx.close()

    if ret != RET_OK:
        return {"ok": False, "error": str(data)}

    flows = []
    if not data.empty:
        for _, row in data.iterrows():
            flows.append({
                "cashflow_id": str(row.get("cashflow_id", "")),
                "clearing_date": str(row.get("clearing_date", "")),
                "settlement_date": str(row.get("settlement_date", "")),
                "currency": str(row.get("currency", "")),
                "cashflow_type": str(row.get("cashflow_type", "")),
                "cashflow_direction": str(row.get("cashflow_direction", "")),
                "cashflow_amount": float(row.get("cashflow_amount", 0)),
                "cashflow_remark": str(row.get("cashflow_remark", "")),
                "is_principal": is_principal_flow(row),
                "is_currency_exchange": is_currency_exchange_flow(row)
            })

    return {
        "ok": True,
        "clearing_date": clearing_date,
        "flows": flows
    }
