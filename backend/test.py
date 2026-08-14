# 查流水（详细版）
from moomoo import *

trd_ctx = OpenSecTradeContext(
    filter_trdmarket=TrdMarket.US,
    host="127.0.0.1",
    port=11111,
    security_firm=SecurityFirm.FUTUAU
)

ret, data = trd_ctx.get_acc_cash_flow(
    clearing_date="2026-01-06",
    trd_env=TrdEnv.REAL,
    cashflow_direction=CashFlowDirection.NONE
)

if ret == RET_OK and not data.empty:
    print("\n===== 原始 DataFrame =====")
    print(data.to_string())  # 👈 打印全部字段

    print("\n===== 逐条解析 =====")
    for _, row in data.iterrows():
        print("日期:", row["clearing_date"])
        print("币种:", row["currency"])
        print("类型:", row["cashflow_type"])
        print("方向:", row["cashflow_direction"])
        print("金额:", row["cashflow_amount"])
        print("备注:", row["cashflow_remark"])
        print("-" * 50)

else:
    print("error or empty:", data)

trd_ctx.close()