from fastapi import FastAPI
from contextlib import asynccontextmanager
from moomoo import *
from config import BACKEND_PUBLIC_URL, HOST, PORT
from principal import init_principal_cache
from routes.account import router as account_router
from routes.positions import router as positions_router
from routes.quote import router as quote_router
from routes.account import fetch_account_snapshot
from routes.market_status import router as market_status_router
from routes.market_intraday import router as market_intraday_router
from routes.orders import router as orders_router
from routes.advisor import router as advisor_router
from market_rt_data import sync_market_intraday_cache
from deal_cache import start_deal_push_listener, stop_deal_push_listener
from advisor_engine import build_advisor_report, sync_advisor_klines
from apscheduler.schedulers.background import BackgroundScheduler
from datetime import datetime
from zoneinfo import ZoneInfo
from asset_snapshots import (
    is_snapshot_empty,
    get_latest_closed_trading_date,
    upsert_snapshot
)
from routes.snapshots import router as snapshots_router

scheduler = BackgroundScheduler(timezone=ZoneInfo("America/New_York"))


def record_initial_asset_snapshot_if_needed():
    if not is_snapshot_empty():
        return

    today = datetime.now(ZoneInfo("America/New_York")).date()
    snapshot = fetch_account_snapshot()
    if snapshot is None:
        print("首次资产快照获取失败")
        return

    created = upsert_snapshot(
        trading_date=today.isoformat(),
        total_assets=snapshot["total_assets"],
        principal=snapshot["principal"]
    )
    print("首次资产快照已记录" if created else "首次资产快照已更新")


def record_daily_asset_snapshot():
    trading_date = get_latest_closed_trading_date()
    if trading_date is None:
        print("还没有可记录的已收盘交易日")
        return

    snapshot = fetch_account_snapshot()
    if snapshot is None:
        print("获取账户资产失败")
        return
    created = upsert_snapshot(
        trading_date=trading_date.isoformat(),
        total_assets=snapshot["total_assets"],
        principal=snapshot["principal"]
    )
    print("收盘资产快照已记录" if created else "收盘资产快照已更新")


def sync_market_intraday_if_needed():
    try:
        result = sync_market_intraday_cache()
        if result.get("synced"):
            print(f"大盘分时已同步: {result['trading_date']} {result['source']}")
    except Exception as exc:
        print(f"大盘分时同步失败: {exc}")


def refresh_advisor_after_close():
    try:
        sync_result = sync_advisor_klines()
        report = build_advisor_report()
        print(
            "智能持仓建议已刷新: "
            f"{sync_result.get('count', 0)} K线任务, "
            f"组合风险 {report.get('portfolio', {}).get('risk_score')}"
        )
    except Exception as exc:
        print(f"智能持仓建议刷新失败: {exc}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    trd_ctx = OpenSecTradeContext(
        filter_trdmarket=TrdMarket.US,
        host=HOST,
        port=PORT,
        security_firm=SecurityFirm.FUTUAU
    )
    init_principal_cache(trd_ctx)
    trd_ctx.close()
    record_initial_asset_snapshot_if_needed()
    scheduler.add_job(
        record_daily_asset_snapshot,
        "cron",
        day_of_week="mon-fri",
        hour=16,
        minute=10,
        timezone=ZoneInfo("America/New_York"),
        id="daily_asset_snapshot",
        replace_existing=True
    )
    scheduler.add_job(
        sync_market_intraday_if_needed,
        "interval",
        minutes=1,
        id="market_intraday_sync",
        replace_existing=True
    )
    scheduler.add_job(
        refresh_advisor_after_close,
        "cron",
        day_of_week="mon-fri",
        hour=16,
        minute=25,
        timezone=ZoneInfo("America/New_York"),
        id="advisor_after_close",
        replace_existing=True
    )
    scheduler.start()
    start_deal_push_listener()
    # 启动时也检查一次，避免后端刚好在收盘后才打开
    record_daily_asset_snapshot()
    sync_market_intraday_if_needed()
    refresh_advisor_after_close()
    print(f"🚀 后端启动完成: {BACKEND_PUBLIC_URL}")
    yield
    stop_deal_push_listener()
    scheduler.shutdown()
    print("🛑 后端关闭")
app = FastAPI(lifespan=lifespan)


@app.get("/")
def home():
    return {
        "message": "Moomoo backend is running",
        "base_url": BACKEND_PUBLIC_URL,
        "opend_host": HOST,
        "opend_port": PORT
    }


app.include_router(account_router)
app.include_router(positions_router)
app.include_router(quote_router)
app.include_router(snapshots_router)
app.include_router(market_status_router)
app.include_router(market_intraday_router)
app.include_router(orders_router)
app.include_router(advisor_router)
