import json
import os
from datetime import datetime, date, timedelta
from zoneinfo import ZoneInfo

import pandas_market_calendars as mcal

from config import DATA_DIR

SNAPSHOT_FILE = DATA_DIR / "asset_snapshots.json"
nyse = mcal.get_calendar("NYSE")


def is_us_trading_day(day: date) -> bool:
    schedule = nyse.schedule(
        start_date=day.isoformat(),
        end_date=day.isoformat()
    )
    return not schedule.empty


def get_last_market_close_time(day: date):
    schedule = nyse.schedule(
        start_date=day.isoformat(),
        end_date=day.isoformat()
    )

    if schedule.empty:
        return None

    close_time_utc = schedule.iloc[0]["market_close"]
    return close_time_utc.to_pydatetime()


def get_latest_closed_trading_date(now_utc=None):
    if now_utc is None:
        now_utc = datetime.now(ZoneInfo("UTC"))

    today = now_utc.date()
    start = today - timedelta(days=10)
    schedule = nyse.schedule(
        start_date=start.isoformat(),
        end_date=today.isoformat()
    )

    if schedule.empty:
        return None

    closed_schedule = schedule[schedule["market_close"] <= now_utc]
    if closed_schedule.empty:
        return None

    return closed_schedule.index[-1].date()


def load_snapshots():
    if not os.path.exists(SNAPSHOT_FILE):
        return []

    with open(SNAPSHOT_FILE, "r") as f:
        return json.load(f)


def save_snapshots(snapshots):
    with open(SNAPSHOT_FILE, "w") as f:
        json.dump(snapshots, f, indent=2)


def is_snapshot_empty() -> bool:
    return len(load_snapshots()) == 0


def has_snapshot_for_date(trading_date: str) -> bool:
    return any(
        snapshot.get("trading_date") == trading_date
        for snapshot in load_snapshots()
    )


def get_latest_valid_principal(min_principal: float = 1000.0):
    for snapshot in reversed(load_snapshots()):
        try:
            principal = float(snapshot.get("principal", 0))
        except (TypeError, ValueError):
            continue
        if principal >= min_principal:
            return principal
    return None


def upsert_snapshot(trading_date: str, total_assets: float, principal: float):
    snapshots = load_snapshots()
    now = datetime.now(ZoneInfo("UTC")).isoformat()

    for snapshot in snapshots:
        if snapshot["trading_date"] == trading_date:
            snapshot["recorded_at"] = now
            snapshot["total_assets"] = total_assets
            snapshot["principal"] = principal
            save_snapshots(snapshots)
            return False

    snapshots.append({
        "trading_date": trading_date,
        "recorded_at": now,
        "total_assets": total_assets,
        "principal": principal
    })

    save_snapshots(snapshots)
    return True
