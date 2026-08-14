from fastapi import APIRouter
from asset_snapshots import (
    get_latest_closed_trading_date,
    has_snapshot_for_date,
    load_snapshots,
    upsert_snapshot
)

router = APIRouter()


@router.get("/asset_snapshots")
def get_asset_snapshots():
    refresh_latest_closed_snapshot_if_missing()
    return {
        "ok": True,
        "snapshots": load_snapshots()
    }


@router.post("/asset_snapshots/refresh_latest")
def refresh_latest_asset_snapshot():
    updated = refresh_latest_closed_snapshot(force=True)
    return {
        "ok": updated,
        "snapshots": load_snapshots()
    }


def refresh_latest_closed_snapshot_if_missing():
    refresh_latest_closed_snapshot(force=False)


def refresh_latest_closed_snapshot(force: bool = False):
    trading_date = get_latest_closed_trading_date()
    if trading_date is None:
        return False

    trading_date_str = trading_date.isoformat()
    if not force and has_snapshot_for_date(trading_date_str):
        return False

    from routes.account import fetch_account_snapshot

    snapshot = fetch_account_snapshot()
    if snapshot is None:
        print("补记最近收盘资产失败：获取账户资产失败")
        return False
    if snapshot.get("principal_guarded"):
        print("跳过资产快照写入：本金触发历史兜底保护", trading_date_str)
        return False

    upsert_snapshot(
        trading_date=trading_date_str,
        total_assets=snapshot["total_assets"],
        principal=snapshot["principal"]
    )
    print("刷新最近收盘资产:" if force else "补记最近收盘资产:", trading_date_str)
    return True
