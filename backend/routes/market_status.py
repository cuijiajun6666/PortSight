# routes/market_status.py
from datetime import datetime, time as dt_time
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Response as FastAPIResponse
from moomoo import *
import pandas_market_calendars as mcal

from config import HOST, PORT

router = APIRouter()
NYSE = mcal.get_calendar("NYSE")
NY_TZ = ZoneInfo("America/New_York")
UTC_TZ = ZoneInfo("UTC")


def get_us_market_session(now=None):
    now = now or datetime.now(UTC_TZ)
    now_utc = now.astimezone(UTC_TZ)
    now_ny = now.astimezone(NY_TZ)

    schedule = NYSE.schedule(
        start_date=now_ny.date().isoformat(),
        end_date=now_ny.date().isoformat()
    )

    if schedule.empty:
        return {
            "session": "closed",
            "display_status": "休市",
            "is_market_open": False,
            "is_regular_open": False,
            "is_extended_open": False,
            "is_trading_day": False,
            "now_new_york": now_ny.isoformat(),
        }

    market_open = schedule.iloc[0]["market_open"].to_pydatetime()
    market_close = schedule.iloc[0]["market_close"].to_pydatetime()
    premarket_open = datetime.combine(now_ny.date(), dt_time(4, 0), NY_TZ).astimezone(UTC_TZ)
    after_hours_close = datetime.combine(now_ny.date(), dt_time(20, 0), NY_TZ).astimezone(UTC_TZ)

    is_regular_open = market_open <= now_utc < market_close
    is_premarket = premarket_open <= now_utc < market_open
    is_after_hours = market_close <= now_utc < after_hours_close
    is_extended_open = is_premarket or is_after_hours

    if is_regular_open:
        session = "regular"
        display_status = "盘中"
    elif is_premarket:
        session = "premarket"
        display_status = "盘前"
    elif is_after_hours:
        session = "after_hours"
        display_status = "盘后"
    else:
        session = "closed"
        display_status = "休市"

    return {
        "session": session,
        "display_status": display_status,
        "is_market_open": is_regular_open or is_extended_open,
        "is_regular_open": is_regular_open,
        "is_extended_open": is_extended_open,
        "is_trading_day": True,
        "now_new_york": now_ny.isoformat(),
        "regular_open": market_open.isoformat(),
        "regular_close": market_close.isoformat(),
        "extended_close": after_hours_close.isoformat(),
    }


@router.get("/market_status")
def get_market_status(response: FastAPIResponse):
    response.headers["Cache-Control"] = "no-store"
    quote_ctx = OpenQuoteContext(host=HOST, port=PORT)

    ret, data = quote_ctx.get_global_state()
    quote_ctx.close()

    if ret != RET_OK:
        return {"ok": False, "error": str(data)}

    return {
        "ok": True,
        **get_us_market_session(),
        "market_us": data.get("market_us"),
        "market_us_raw": data.get("market_us"),
        "qot_logined": data.get("qot_logined"),
        "trd_logined": data.get("trd_logined"),
        "program_status_type": data.get("program_status_type")
    }
