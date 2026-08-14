from fastapi import APIRouter
from moomoo import *

from config import HOST, PORT
from utils import safe_float

router = APIRouter()


def normalize_code(symbol: str) -> str:
    symbol = symbol.strip().upper()
    if "." in symbol:
        return symbol
    return f"US.{symbol}"


@router.get("/quote")
def get_quote(symbol: str):
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)

    code = normalize_code(symbol)

    ret_sub, sub_msg = quote_ctx.subscribe(
        [code],
        [SubType.QUOTE],
        subscribe_push=False,
        extended_time=True
    )

    if ret_sub != RET_OK:
        quote_ctx.close()
        return {
            "ok": False,
            "error": str(sub_msg),
            "code": code
        }

    ret, data = quote_ctx.get_stock_quote([code])
    quote_ctx.close()

    if ret != RET_OK or data.empty:
        return {
            "ok": False,
            "error": str(data),
            "code": code
        }

    row = data.iloc[0]

    print("====== QUOTE DEBUG ======")
    print("code:", code)
    print("last_price:", row.get("last_price"))
    print("prev_close:", row.get("prev_close_price"))
    print("pre_price:", row.get("pre_price"))
    print("after_price:", row.get("after_price"))
    print("overnight_price:", row.get("overnight_price"))
    print("==========================")

    pre_price = safe_float(row.get("pre_price"))
    after_price = safe_float(row.get("after_price"))
    overnight_price = safe_float(row.get("overnight_price"))

    last_price = safe_float(row.get("last_price"))
    open_price = safe_float(row.get("open_price"))
    high_price = safe_float(row.get("high_price"))
    low_price = safe_float(row.get("low_price"))
    prev_close = safe_float(row.get("prev_close_price"))
    if prev_close <= 0:
        prev_close = safe_float(row.get("last_close_price"))
    if prev_close <= 0:
        prev_close = last_price

    # ✅ 只用最新价
    display_price = last_price

    display_open = open_price if open_price > 0 else prev_close
    display_high = high_price if high_price > 0 else prev_close
    display_low = low_price if low_price > 0 else prev_close

    change = display_price - prev_close if prev_close > 0 else 0
    change_percent = change / prev_close * 100 if prev_close > 0 else 0

    return {
        "ok": True,
        "code": str(row.get("code", code)),
        "name": str(row.get("name", "")),

        "price": display_price,
        "prev_close_price": prev_close,
        "previous_close": prev_close,

        "open_price": display_open,
        "high_price": display_high,
        "low_price": display_low,

        "change": change,
        "change_percent": change_percent,

        "raw_last_price": last_price,
        "data_date": str(row.get("data_date", "")),
        "data_time": str(row.get("data_time", "")),
        "volume": safe_float(row.get("volume")),
        "turnover": safe_float(row.get("turnover")),

        "pre_price": pre_price,
        "after_price": after_price,
        "overnight_price": overnight_price,

    }
