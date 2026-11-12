# 实时交易数据格式（交易 · 实时）

量化系统要推给 PortSight 的内容，用于 Mac / iOS 的「交易 · 实时」页。App 只读：不下单、不撤单、不改单，不保存交易所密钥。

对应的 Swift 模型在 `PortSightKit/Sources/PortSightKit/Live/LiveModels.swift`，全部 `Codable`，字段名与下文一致。

## 通用约定

- 时间一律 UTC 毫秒（`1794000000000`），字段名 snake_case。
- 金额单位是账户币种（`currency`，目前都是 `USDT`）；数量单位是「张」，1 张 = 1 个币。
- 方向：持仓 `side` / `position_side` 用 `long` / `short`；委托和成交的 `side` 用 `buy` / `sell`。
- 收益率字段是小数：`0.031` 表示 +3.1%。
- 交易编号 `trade_id` 从开仓起贯穿这一笔交易的所有委托、成交和持仓，平仓后就是 `closed_trades[].trade.id`。
- 没有的值写 `null` 或不写，不要写 0 冒充。

## 一、快照 `snapshot`

连上时发一次，之后 App 可以随时再要。只放当前状态，不放完整历史。

```json
{
  "t": 1794000000000,
  "accounts": [ … ],
  "positions": [ … ],
  "orders": [ … ],
  "models": [ … ],
  "fills": [ … ],
  "closed_trades": [ … ]
}
```

`fills`（最近的成交，旧的在前）和 `closed_trades`（已平仓交易）可选，用于打开页面时画出之前做过什么；建议各给最近 14 天。

### accounts

| 字段 | 类型 | 说明 |
|---|---|---|
| id | string | `paper-1` / `live-1` / `shadow-1` |
| kind | string | `paper` 模拟盘、`live` 实盘、`shadow` 影子账本 |
| name | string | 显示名，例如「模拟盘 · 主账户」 |
| currency | string | `USDT` |
| balance | number? | 钱包余额（入金 + 已实现 − 手续费） |
| equity | number? | 权益 = 余额 + 未实现盈亏 |
| available | number? | 可用 |
| margin_used | number? | 保证金占用（含挂单冻结） |
| today_pnl | number? | 今日盈亏（UTC 0 点起，权益变化） |
| unrealized_pnl | number? | 未实现盈亏 |
| today_fee | number? | 今日手续费 |
| updated_at | number | 毫秒 |

### positions（当前持仓）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | string | 持仓编号 |
| account_id, model | string | 所属账户和模型（例如 `v4 G263`） |
| contract | string | `BTCUSDT` |
| instrument | string | `perpetual`（显示「永续」）或 `spot` |
| side | string | `long` / `short` |
| size | number | 张数 |
| leverage | number | 杠杆倍数 |
| entry_px | number | 开仓均价 |
| mark_px | number | 标记价 |
| liquidation_px | number? | 强平价 |
| unrealized_pnl | number | 未实现盈亏 |
| unrealized_pct | number | 按保证金的收益率 |
| margin | number | 保证金 |
| stop_px, target_px | number? | 当前止损 / 止盈价 |
| opened_at | number | 开仓时间 |
| trade_id | string | 交易编号 |
| size_path | array | `[{t, w, why}]`，同回测 `size_path`：w 为占权益比例，空头为负；why 为 `open` / `add` / `reduce` / `partial_tp` |
| stops, targets | array | `[{t, px}]`，止损 / 止盈每次移动 |
| realized_pnl, fee | number | 这笔交易已经实现的盈亏和已付手续费 |

### orders（当前委托）

只放等待中的委托（`new` / `partially_filled`）；状态变化走事件流。

| 字段 | 类型 | 说明 |
|---|---|---|
| id, account_id, model, contract | string | |
| type | string | `market` / `limit` / `stop` / `take_profit` |
| side | string | `buy` / `sell` |
| position_side | string | 开或平的是哪个方向的仓 |
| reduce_only | bool | 只减仓（止损、止盈、平仓单为 true） |
| price | number? | 限价或触发价；市价单为 null |
| size, filled | number | 张数、已成交张数 |
| status | string | `new` / `partially_filled` / `filled` / `canceled` / `rejected` |
| created_at, updated_at | number | |
| trade_id | string? | 已关联的交易 |

### models（模型状态）

| 字段 | 类型 | 说明 |
|---|---|---|
| account_id, model | string | |
| state | string | `running` 运行中 / `paused` 暂停 / `error` 出错 |
| last_run, next_run | number? | 上次 / 下次运行 |
| signals | object | 最新信号值，例如 `{"BTC mu_4h": 0.0021, "entry_thr": 0.004}`；影子账本必须为 `{}` |
| checks | array | `[{name, pass, detail}]`，pass 为 true 显示「过」，false 显示「不过」 |
| signals_today, signals_total | int | 信号次数 |
| contracts | array | 可交易的合约 |
| message | string? | 出错原因 |

### closed_trades（已平仓交易）

```json
{ "account_id": "paper-1", "model": "v4 G263", "realized_pnl": 312.4, "fee": 18.2, "trade": { … } }
```

`trade` 与回测导出的 `trades.json` 一行完全相同（`id, symbol, side, entry_t, entry_px, exit_t, exit_px, exit_reason, size_path, stops, targets, pnl_gross, fee, funding, pnl_net, mfe, mae, hold_h, signals_at_entry`），收益类字段是占开仓时权益的比例，K 线图用同一个框画它。

## 二、事件流 `events`（只追加）

每条事件一个 JSON，`seq` 只增不减；App 记住最后一个 `seq`，重连时从它之后补发。

```json
{ "seq": 1842, "t": 1794000012000, "type": "fill", "account_id": "paper-1", "fill": { … } }
```

| type | 带的字段 | 用途 |
|---|---|---|
| `fill` | `fill` | 新成交；App 用它弹出「v4 G263 开多 BTCUSDT 0.12 张 @ 68,420.5」 |
| `order` | `order` | 委托新建、改价、成交、撤销（整条最新状态） |
| `position` | `position` | 持仓新开或变化（整条最新状态） |
| `position_closed` | `position_id` | 持仓已平；随后应有对应的 `fill` |
| `model` | `model` | 模型状态变化 |
| `bar` | `bar` | 1 分钟 K 线更新（内容同第三节，`account_id` 为空串） |

`fill` 字段：`id, account_id, model, order_id, trade_id, t, contract, side, position_side, action（open / add / reduce / close）, price, size, fee, realized_pnl（本笔实现盈亏，未扣手续费；开仓、加仓为 0）, reason`。
`reason` 取值：`signal`、`add`、`reduce`、`partial_tp`、`take_profit`、`stop_loss`、`signal_exit`、`signal_reverse`、`time_exit`、`risk_cut`。

标记价变化不必逐笔推：App 用 K 线收盘价重算未实现盈亏；快照里的 `mark_px` 以量化系统为准。

## 三、K 线 `bars`

只推 1 分钟线，App 自己合成 5 分 / 15 分 / 1 小时。

```json
{ "contract": "BTCUSDT", "timeframe": "1m", "closed": false, "bar": { "t": 1793999960000, "o": 68401.2, "h": 68433.0, "l": 68390.1, "c": 68420.5, "v": 12.4 } }
```

`t` 是这根线的开始时间；这一分钟没走完时 `closed` 为 false，可以反复推同一根。连上时补最近 14 天（可以直接给 5 分钟线，`timeframe: "5m"`）。

## 四、影子账本规则（前向封存）

影子账本（`kind: shadow`：v3.0 主线和挑战者）从 2026-10-22 起在前向封存期，结果 2027-05-06 开封。在那之前：

- 只发 `models`：状态、上次 / 下次运行、信号次数、检查过 / 不过；`signals` 为空对象。
- 账户的 `balance / equity / available / margin_used / today_pnl / unrealized_pnl / today_fee` 一律为 null。
- 不发它的 `positions`、`orders`、`fills`、`closed_trades`、`position*` 事件。

App 读取时还会再封一次（`LiveSnapshot.sealed()`）：就算误发，也不会显示收益、盈亏、净值和交易框。模拟盘和实盘是自己的钱，所有字段照常显示。

## 五、以后怎么送到 App

和服务器页一样，走已配对的 Mac mini 中继（Tailscale 私网内的 HTTPS，App 不直连交易所，也不碰密钥）：

- `GET /v1/live/snapshot` → 快照（已按第四节封存）。
- `GET /v1/live/events?after=<seq>` → 之后的事件，长轮询或 Server-Sent Events。
- `GET /v1/live/bars?contract=BTCUSDT&tf=1m&since=<t>` → K 线补齐；之后的 1 分钟线随事件流推送（`type: "bar"`，`bar` 字段内容同第三节，`account_id` 为空串）。

中继只转发量化系统写好的数据，只提供 GET。在中继接好之前，App 用内置数据（`LiveFeed`）跑这个页面。
