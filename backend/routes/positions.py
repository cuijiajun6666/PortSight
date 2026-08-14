from fastapi import APIRouter
from moomoo import *

from config import HOST, PORT

router = APIRouter()


def safe_float(value):
    try:
        return float(value)
    except:
        return 0.0


def fetch_stock_types(codes):
    if not codes:
        return {}

    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)
    ret, data = quote_ctx.get_stock_basicinfo(
        Market.US,
        code_list=codes
    )
    quote_ctx.close()

    if ret != RET_OK:
        print("获取股票类型失败:", data)
        return {}

    return {
        str(row.get("code", "")): str(row.get("stock_type", ""))
        for _, row in data.iterrows()
    }


@router.get("/positions")
def get_positions():
    trd_ctx = OpenSecTradeContext(
        filter_trdmarket=TrdMarket.US,
        host=HOST,
        port=PORT,
        security_firm=SecurityFirm.FUTUAU
    )

    ret, data = trd_ctx.position_list_query(trd_env=TrdEnv.REAL)
    trd_ctx.close()

    if ret != RET_OK:
        return {"ok": False, "error": str(data)}

    positions = []
    codes = [str(row.get("code", "")) for _, row in data.iterrows()]
    stock_types = fetch_stock_types(codes)

    for _, row in data.iterrows():
        code = str(row.get("code", ""))
        stock_type = stock_types.get(code, "")
        is_etf = stock_type == SecurityType.ETF

        qty = safe_float(row.get("qty"))
        market_val = safe_float(row.get("market_val"))

        diluted_cost = safe_float(row.get("diluted_cost"))
        if diluted_cost <= 0 and qty > 0:
            diluted_cost = market_val / qty

        realized_pl = safe_float(row.get("realized_pl"))
        unrealized_pl = safe_float(row.get("unrealized_pl"))
        pl_ratio = safe_float(row.get("pl_ratio"))

        positions.append({
            "code": code,
            "name": str(row.get("stock_name", "")),
            "stock_type": stock_type,
            "is_etf": is_etf,
            "asset_class": "ETF" if is_etf else "STOCK",
            "qty": qty,

            # 摊薄成本价
            "cost_price": diluted_cost,

            "market_val": market_val,

            # 分开返回
            "realized_pl": realized_pl,
            "unrealized_pl": unrealized_pl,

            # 保留旧字段，SwiftUI 现有 pnl 可以继续用
            "pl_val": unrealized_pl,
            "pl_ratio": pl_ratio
        })

    return {
        "ok": True,
        "positions": positions
    }
