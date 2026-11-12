
# PortSight（iOS）综合终端：开发计划

> 这份计划写给接手开发 iOS 版的 AI 对话，开发者看不到之前的讨论，按本文执行即可。
> 建议存为 `/Users/chriscui/Desktop/Xcode/PortSight/UNIFIED_TERMINAL_PLAN.md`。
> 同一套计划还有两份：Mac 版（`/Users/chriscui/Desktop/Xcode/PortsightMac/UNIFIED_TERMINAL_PLAN.md`）和个人网站（`/Users/chriscui/Documents/GitHub/coffeeheart-site/SERVER_ENTRY_PLAN.md`）。
> 所有回复和界面文字都用中文。

## 0. 用户 10-30 夜的硬性要求（优先于下文任何一条）

1. **OKX 和 moomoo 的旧连接保留，不删、不停用。**
   - OKX：现在用设备钥匙串里的只读密钥直连交易所的方式保留。可以把 OKX 客户端**升级到最新的 v5 接口**：签名、错误码、强制解包都可以改；模拟盘的 header 改成开关，不要写死 `env: .real`。但"用只读密钥直连"这条路不能拿掉。
   - moomoo：旧的后端连接（`BackendConfig`、account、positions、quote、订单、advisor 这些接口）**原样保留**。用户以后可能在 moomoo 上跑股票实盘。默认地址、协议、认证方式都不在本次改动范围内，不要删，也不要改成 relay。
   - 新增的 relay 数据源和旧连接**并存**：设置里分开显示（"量化服务器（relay）"、"OKX 直连"、"moomoo 后端"），各自能单独开关。
   - 以后就算在 moomoo 上跑实盘，下单程序也在 Mac mini 上运行。App 仍然只看不下单，不要因为 moomoo 有订单接口就在 App 里加下单按钮。
2. **App 从"资产查看器"改成"个人综合入口"**，左栏和标签栏按"做什么事"重排，见第 0.1 节。原来的"全部 / 美股 / 加密"降为"资产"下面的二级筛选。

### 0.1 信息架构（iOS 和 Mac 共用，PortSightKit 里定义同一个 `Section` 枚举）

| 一级 | 内容 | 数据来源 |
|---|---|---|
| **总览** | 总资产和今日盈亏（默认显示，可用"隐藏金额"开关隐藏）、各策略状态、服务器是否正常、最新 3 条告警；两个快捷按钮：远程桌面、上传照片 | 汇总下面各项 |
| **资产** | 二级：**全部 / 美股 / 加密**（保留原有分法）；再按账户分：OKX、moomoo、以后的 Hyperliquid 钱包等；持仓、历史、资产快照 | OKX 直连、moomoo 后端、relay `/account` |
| **交易** | 加密 v2 各子策略，当前阶段（影子 / 模拟盘 / 实盘）和上线检验进度；股票模拟盘；交易记录；日报周报 | relay `/status`、`/reports/latest`、`/account?line=` |
| **告警** | 全部告警，按 severity 和 category 筛选，标记已读 | relay `/alerts` |
| **服务器** | Mac mini：负载、内存压力、温度、三块盘（内置盘、三星T7、照片）、采集器心跳、重任务队列；AI 服务器状态 | relay `/host`；AI 服务器状态文件（待接口方提供） |
| **云盘** | 照片：打开 Immich 上传和浏览；文件传输说明；存储用量 | Immich 链接、`/host` 里的磁盘数据 |
| **AI** | 资料问答、值班员建议、每日复盘 | 私有 AI 服务器（接口待提供，先做占位） |
| **远程** | 一键打开 Jump Desktop（首选），或 `vnc://`（备用） | 深链，见入口页一节 |
| **设置** | 三个数据源的连接、推送、"隐藏金额"、演示模式开关 | — |

- **Mac**：左侧栏用 `NavigationSplitView`，按上表从上到下排；"资产"可以展开出"全部 / 美股 / 加密"。另加菜单栏 `MenuBarExtra`。
- **iOS**：底部 5 个标签：**总览 · 资产 · 交易 · 服务器 · 更多**。"更多"里放云盘、AI、告警列表、远程、设置。未读告警数显示成总览标签上的角标。
- 还没有数据的分区也要显示，内容统一是"尚未接入"的占位，不要隐藏，以后接上就有数据。

### 0.2 资产显示和 moomoo 后端怎么连（用户 10-30 夜补充）

**资产必须显示。** 终端的第一用途仍然是看自己的资产：
- App 里**默认显示金额**，"隐藏金额"只是一个可选开关，默认关；
- 资产页和总览是 **P0**，和安全清理一起先做；
- 真实资产来自两条旧连接：moomoo 后端（股票）和 OKX 只读直连（加密）。relay 的 `/account` 只是量化模拟盘的账户，单独一区显示，不和真实资产相加；
- 只有推送和锁屏不带金额，因为推送要经过苹果的服务器，还会显示在锁屏上。

**moomoo 后端是什么**：用户自己写的 FastAPI 服务，代码在 GitHub 仓库 `cuijiajun6666/PortSight` 的 `backend/`（部署脚本里引用的是 `cuijiajun6666/PortSight-Backend`，内容相同）。它通过 moomoo OpenD 读取账户数据。
- OpenD 和后端跑在同一台服务器上。OpenD 监听 `127.0.0.1:11111`，**这个端口绝不能开到公网**。
- 后端监听 `0.0.0.0:8000`，以前的地址是 `http://45.63.31.248:8000`。这是用户以前那台服务器，**以后会重新配置，App 里把地址做成设置项，不要写死**。

**部署（Ubuntu 服务器，一条命令）**，见仓库 `backend/README.md`：
```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://<服务器IP>:8000 INSTALL_OPEND=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/backend/deploy/bootstrap_ubuntu.sh)"
```
- 脚本做的事：装依赖；克隆到 `/opt/moomoo-backend/app`；建 systemd 服务 `moomoo-backend`（uvicorn，端口 8000）；用 ufw 放行 8000；`INSTALL_OPEND=1` 时再跑 `install_opend_ubuntu.sh`，从 moomoo 官网下载 OpenD，装在 `/opt/moomoo-opend`，建服务 `moomoo-opend`。
- 第一次登录要在 SSH 终端里输入 moomoo 账号和密码，再到 moomoo App 里确认设备验证。看到 OpenD 的 `>>>` 提示后输入 `exit`，脚本会转成后台运行并自动校验。
- 校验：`bash /opt/moomoo-backend/app/backend/deploy/verify_server.sh`；日志：`journalctl -u moomoo-backend -f`、`journalctl -u moomoo-opend -f`。
- 可选参数 `GITHUB_TOKEN=...`：每天 22:30 UTC 把运行数据推回 GitHub。**不要开**，原因见下面的"注意"。

**App 用到的接口**（都是 GET，没有认证）：
- `/account`、`/positions`、`/quote`、`/asset_snapshots`、`/market_status`、`/market_intraday`；
- `/orders/open`、`/orders/history`、`/deals`、`/deals/history`；
- `/advisor/summary`、`/advisor/suggestions`、`/advisor/symbol`、`/advisor/alerts`、`/advisor/watchlist`。

后端**没有下单接口**。App 只用 GET；带 POST 或 PATCH 的 advisor 维护接口不要在 App 里做按钮。

**注意（给以后重新配置的对话）**：
1. 这个后端**没有任何认证**，而且对公网开着 8000 端口，谁知道 IP 都能读到账户、持仓和成交。以后重新部署时建议改成两种做法之一：
   - 部署在 Mac mini 上（桌面已经有 `moomoo_OpenD_10.4.6408_Mac`），只监听 127.0.0.1，经 `tailscale serve` 访问，端口不要和 relay 的 443 冲突；
   - 仍放在 VPS 上，但后端只监听 Tailscale 地址，或者加一个令牌认证。
   App 里要能同时支持 http（旧 VPS）和 https（Tailscale），由用户在设置里填。
2. `push_runtime_data.sh` 会把 `asset_snapshots.json`、`trade_deals.json` 等运行数据推到 GitHub，而 `PortSight` 和 `PortSight-Backend` **两个仓库现在都是公开的**。是否改成私有仓库、是否清理历史，由用户本人决定；开发对话不要去改仓库设置。
3. 以后要是在 moomoo 上跑实盘，下单程序放在 Mac mini 上，经 OpenD 下单；App 仍然只看。

## 1. 目标与范围

把 PortSight 做成用户本人的"个人终端"，只读，在一个 App 里看到下面这些：

1. 各交易所和券商的资产与持仓（只读）。
2. 量化策略的表现，以及模拟盘或实盘的运行状态。
3. 告警（APNs 推送 + App 内列表）。
4. Mac mini 服务器状态：负载、内存压力、温度、磁盘（内置盘 / 三星 T7 主盘 / 备份 / 照片）、采集器心跳、重任务队列。
5. 私有 AI 服务器状态。
6. 快捷入口：Immich 照片上传、远程桌面、AI 控制台。

**用户情况**：真实可投资金约 20–30 万美元。股票模拟盘配置 `portfolio_paper_v1.json` 用的是名义 100 万美元。所以模拟盘只用收益率和百分比展示，不要和真实账户的金额相加。

**不做的事（硬规则）**：
- 不下单、不撤单。
- 不改风控参数。
- 不重启或停止任何交易进程。
- 不实现远程桌面协议。
- 不新增任何交易所或券商的**交易**密钥。OKX 只读密钥照旧放在设备钥匙串里（见第 0 节）。

## 2. 现状（2026-10-30 只读侦察）

**工程基本信息**
- 工程：`/Users/chriscui/Desktop/Xcode/PortSight/PortSight.xcodeproj`，三个 target：PortSight、PortSightTests（Swift Testing）、PortSightUITests（只有模板）。
- 部署目标 iOS 26.5，Swift 5 语言模式，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，没有 SPM 依赖。
- Bundle ID 是 `-66.PortSight`（开头是横杠），Team 是 VNCWV57XL4。请让用户确认 Bundle ID 是否要改。改了会影响 APNs topic。

**文件归属是混合方式**
- 只有 `PortSight/Server/` 和两个测试目录是"文件夹同步组"。
- 在其他目录新建的 `.swift` 文件，要手动加进 target 才会参与编译。

**Git**
- 只有一个 `Initial Commit`，大量文件处于未跟踪或已暂存状态。
- 开工前先问用户要不要先提交现有工作区。没有用户同意，不要提交，也不要推送。

**页面**
- 标签页（`Views/ContentView.swift`）：Dashboard、Positions、Activity（演示）、服务器、Analysis。
- 设置页在 `Views/设置？.swift`，结构体还叫 `名字待定2`。`AsseetDetailView` 拼写有误。`Item` 模板模型仍在 SwiftData schema 里。

**演示模式**
- `Demo/DemoPortfolioData.swift` 里写死了 `static let enabled = true`，股票和组合页面全是假数据。
- `DemoOfflineProtocol` 会拦掉共享 session 的请求。

**老后端**
- 走 moomoo 老协议，经 `连接/BackendConfig.swift` 访问，请求不带任何认证。
- `defaultBaseURL` 已经清空，只接受 https，老 IP 已删（10-30 监控会话改的）。用户要求 moomoo 旧连接保留：如果这样改让 moomoo 连不上了，要恢复到能用，地址由用户在设置里填。有测试断言地址里不含 "45.63"。

**服务器页（真实数据）**
- 代码在 `Server/`：ServerConnection、ServerModels、ServerView、ServerSample、ServerPush、OKXCredentials。
- 目前只用了三个接口：`POST /devices`、`GET /host`、`GET /alerts?since=`。每次按时间拉 7 天的告警，没有用 cursor。
- 每 60 秒刷新一次。上次成功的 `/host` 结果缓存在 `Application Support/PortSight/server_host.json`。

**OKX**
- `OKXClient` 直连 `https://app.okx.com`，带签名，写死 `env: .real`，`baseURL` 用了强制解包。
- 只读密钥存在手机钥匙串（设置 → "OKX 只读密钥"）。
- 公共行情走 `https://www.okx.com`。
- **以前硬编码过的那把 OKX 密钥由用户本人轮换**，开发者不要去找它，也不要碰它。

**其他现状**
- IBKR、Hyperliquid 账户：完全没有。
- 推送：entitlements 里是 `aps-environment = development`，开了 `remote-notification` 后台模式，开关默认关闭。
- 不安全的地方：
  - Info.plist 里 `NSAllowsArbitraryLoads = true`；
  - `Views/其他/CompanyLogo.swift` 写死了 logo.dev 的公开 key（含一个 key，不要复制到别处）；
  - iCloud entitlement 开着，但容器列表是空的。

## 3. 架构

### 3.1 共享 Swift Package：PortSightKit（本对话负责创建）

- 位置：`/Users/chriscui/Desktop/Xcode/PortSightKit`（本地包），iOS 和 Mac 两个工程都以本地依赖引用。
- `platforms: [.iOS("26.5"), .macOS("27.0")]`，Swift 5 语言模式。
- **只依赖** Foundation、Security、CryptoKit，不引入任何 UIKit 或 AppKit。

**模块划分**

1. `PortSightCore`
   - 所有 relay 数据模型：字段全部可选，遇到未知字段不报错，统一处理 `available: false`。
   - `RelayClient`：actor，配合 ephemeral URLSession，禁止重定向。
   - `ServerKeychain`、`ServerFreshness`、`ServerDates`（解析 Python isoformat，支持微秒和时区）。
   - URL 校验：只接受 https 的 origin，不能带用户名密码、路径或 query；不是 `.ts.net` 的地址要给出警告。
   - HMAC 工具：从现有 OKX 签名代码迁入。附一个测试向量，与 relay 的 `notify.py signature()` 格式一致：`hex(HMAC-SHA256(secret, ts + "." + body))`。**App 不持有任何生产者密钥，不调用 `POST /alerts`**，这个工具只为两端算法保持一致。
2. `PortSightMarket`：OKX **公共**行情（`index-tickers`、`candles`、`currencies`），不带密钥。
3. `PortSightDemo`：演示数据的纯数据部分（来自 `DemoPortfolioData.swift`）。

**迁移要求**

- 推送开关目前有引用写在 `ServerConnection` 里（`ServerPush.enabled/tokenKey`），要抽成协议 `PushTokenProvider`，由各个 App 自己实现。
- Mac 版对话**只往包里新增文件**，不改已有的公开 API。要改 API，在本文第 9 节登记，由本对话来改。两边都要跑包里的测试。

### 3.2 数据源：Mac mini 上的 relay（只读，只走 Tailscale）

**地址与传输**
- App 填的地址是 `https://<机器名>.<tailnet>.ts.net`，不带端口。tailscale serve 把 443 转到 `127.0.0.1:8765`。
- 不用公网 IP，不用 HTTP，不用 Funnel。
- 响应是 JSON，带 `Cache-Control: no-store`。错误统一返回 `{"error": "..."}`，状态码有 400、401、404、405、409、413、503。

**配对**
- 用户在 Mac mini 上运行 `python3 -m quant_system.relay pair --state sessions/portsight` 拿到一次性码（5 分钟内有效）。
- App 发 `POST /devices`，body 为 `{"pairing_code", "apns_token": "<hex 或空串>", "digest_hour": 0-23, "digest_minute": 0-59}`，返回 `{"device_token"}`。
- 已配对的设备带 Bearer 再发 `POST /devices`，可以更新 `apns_token` 和摘要时间，返回 `{"registered": true}`。
- 之后所有 GET 都带 `Authorization: Bearer <device_token>`。
- 令牌存钥匙串：service 是 `PortSight.relay`，account 是 relay 的 origin，可访问级别 `AfterFirstUnlockThisDeviceOnly`。

**端点（App 只允许用这些）**

| 端点 | 用途 | 刷新 |
|---|---|---|
| `GET /host` | 服务器状态。内容是 host_status 的 latest.json，另加 `relay_age_seconds` 和 `stale` | 60 秒 |
| `GET /alerts?cursor=<seq>` | 增量告警，返回 `{events, has_more, next_cursor}`，每页最多 500 条 | 60 秒 |
| `GET /status[?line=stock\|crypto\|account_risk]` | 各条线路的运行状态 | 5 分钟 |
| `GET /account[?line=…]` | 资产与持仓 | 5 分钟 |
| `GET /reports/latest?type=daily\|weekly\|monthly[&line=…]` | 复盘报告 | 进入页面时 |
| `GET /advice?symbols=A,B`（最多 50 个） | 模型卡片 | 进入页面时 |

- `cursor` 要持久化，按 relay 地址分开存。
- 第一次没有 cursor 时，可以用 `since` 取最近 7 天，再改用 `next_cursor`。
- relay 每 5 分钟收集一次数据，所以数据最多可能晚约 10 分钟。界面上要显示 `as_of` 和数据有多旧。

**数据结构（已知字段）**

- **事件**：`{id, source, category: trade|safety|risk|data|ops|model|research|review, severity: info|warning|critical, title, detail{}, at}`。主机告警的 id 形如 `host:<键>:<起始时间>[:<severity>|:recovered]`，source 为 `host-status`。
- **host**：
  - `summary{state, active_alerts, heartbeats_ok, heartbeats_problem}`
  - `host{load{m1,m5,m15,per_core_5m}, memory{pressure, free_pct, swap_*}, thermal{cpu_temp_c 可能为 null（要装 macmon）, …}, power{source, kind, percent}, uptime_hours}`
  - `disks{internal|main|backup|photos|local_fallback}`。界面标签：internal = 内置盘，main = 三星 T7（主盘），backup = 备份，photos = 照片。**现在页面只显示 main、backup、local_fallback，要补上 internal 和 photos。**
  - `launchd.jobs`、`heartbeats[]`（state 有 ok、stale、critical、missing、not_installed、error、stopped）
  - `queue.heavy_lock`、`collector_health`、`deadman`、`push`、`alerts_active`、`alerts_recent`
  - `history[[at, load5, mem_free_pct]]`，只有 24 小时
- **status**（加密线）：`as_of, available, last_run_at, last_run_result, mode, stages{}, safe_mode, dead_letters, market_as_of, data_stale, next_rebalance_at, model{available}, live`。其中多项现在是 null，界面显示"—"。
- **status.account_risk**：`… valid_until, stage, lines{线路: {mode, scale}}`。
- **account**：`as_of, available, equity, cash, daily_pnl, drawdown, drawdown_limit, positions[{symbol, sleeve, quantity, market_value, pnl, weight}]`。可能另有 `source, limitations` 字段，这时多项值为 null。
- **report_\***：`as_of, available, type, summary, return, benchmark_return, max_drawdown, turnover, cost, points[{at, equity, benchmark_equity, drawdown}]`。股票版另有 positions、fills、sleeves 等明细；加密版的明细放在 `crypto` 键下。
- **advice 卡片**：`symbol, available, model_version, as_of, evidence, cost_note`，三个先触发概率，`suggested_weight`，`forecast_20d/60d{lower, upper, coverage}`，`add_condition/reduce_condition{historical_win_rate}`，`disclaimer`。

### 3.3 待接口方提供（不要自己编端点，先做"尚未接入"的占位状态）

**待 quant relay 提供**
1. 资产数据现在基本是空的：
   - stock、crypto、account_risk 三条线的 `SEND_APPROVED` 都没打开；
   - **`account.crypto` 没有生产者**；
   - OKX、IBKR、moomoo、Hyperliquid 的只读余额都不经过 relay。
   - 综合资产页要等 relay 新增只读账户投影。投影名称和字段以 relay 为准。
2. `advice` 和 `report_monthly` 没有生产者。
3. 设备管理：现在没有列出设备、吊销、重命名的接口，令牌也不会过期。App 里"断开"只能删本地令牌，界面上要写明这一点。
4. 私有 AI 的心跳还没接进 host_status（private-ai 的 `docs/REVIEW_FIXES.md`，"要量化配合"第 1 条）。接通后会自动出现在 `/host.heartbeats` 里。
5. 没有 WebSocket 或 SSE，也没有长期净值曲线和磁盘、网络的历史序列。

**待 private-ai-server 提供**
- 给 App 用的只读令牌。现在的 `/health`、`/api/status`、`/api/entry` 都要管理员 Basic 认证，**App 不能存管理员密码**。在这之前，私有 AI 只放链接入口。

## 4. 界面与功能（按优先级）

### P0：安全清理和共享包（先做）

1. 删掉 Info.plist 里的 `NSAllowsArbitraryLoads`。
2. OKX 客户端升级到最新 v5 接口（第 0 节）：保留"OKX 只读密钥"入口和钥匙串读取；去掉 `baseURL` 的强制解包；模拟盘 header 改成开关。
3. 演示模式不再写死。改成设置里的开关，默认关闭；关闭后真实页面显示"尚未接入"。
4. 老 moomoo 后端原样保留（第 0 节），和 relay 并存，在设置里分开显示、各自可以开关。
5. 创建 PortSightKit 包，把 Server 模型和客户端迁进去，服务器页改用包里的代码。告警改用 cursor 增量拉取。

### P1：服务器页补全

- 补上内置盘和照片两块磁盘，增加重任务队列卡片。
- 心跳分组显示：runner、sleeve、collector。
- 数据过期时显示红色横幅，每个卡片上标注"距今 N 分钟"。

### P1：量化页（新标签页，或替换演示用的 Activity 页）

- 显示 stock、crypto、account_risk 三条线：模式（模拟盘 / 实盘 / 影子）、上次运行结果、各阶段状态，还有 `account_risk.lines` 的 scale。
- 日报和周报：收益率、基准、最大回撤、换手、成本，再加 `points` 曲线。

### P0：资产页（和安全清理一起先做，见第 0.2 节）

- 真实资产：股票来自 moomoo 后端（`/account`、`/positions`、`/asset_snapshots`），加密来自 OKX 只读直连。量化模拟盘来自 relay 的 `/account?line=…`，单独一区。
- 真实账户和模拟盘分两个区，不合计。
- 支持"全部 / 个人 / 量化"三个范围。真实数据里还没有这个拆分，所以先按 sleeve 和线路来分。
- 设置里加"隐藏金额"开关，**默认关**，也就是默认显示金额。打开以后，切到后台时界面要模糊处理。

### P2：入口页

- **远程桌面**：
  - 首选 Jump Desktop，用 Fluid 协议，连 Tailscale 地址（直连 / Cloudless 模式）。`jump://` 深链的参数格式以 Jump Desktop 官方文档为准，实现前先核对。拿不准时只打开 Jump Desktop App。
  - 备用 `vnc://<机器名>`。
  - UU 远程不放链接，只在帮助里写一句"应急备用，平时关闭"。
- **Immich**：`https://<机器名>.<tailnet>.ts.net:10000`，或者打开 Immich 官方 App（深链格式核实后再用）。
- **AI 控制台**：`https://<机器名>.<tailnet>.ts.net:8443`，用浏览器打开，由用户自己登录。

### P3：其他

- 小组件和锁屏组件：只显示服务器状态和告警数；如果要显示金额，必须跟着"隐藏金额"开关。
- advice 卡片：等有生产者以后再做。
- 私有 AI 状态卡：等只读令牌以后再做。

## 5. 告警和推送

- 继续用现有的 `ServerPush`。推送内容只有固定的中文标签和时间（relay 的 `alert_text.py` 生成），App 不要再往推送里补任何详情。
- 点推送跳到服务器页，详情从 `GET /alerts` 取。这一步走 Tailscale，可以显示完整的 title 和 detail。
- "服务器离线"由 Healthchecks.io 经 ntfy 推送，不走 APNs。App 里只显示 `/host.deadman` 的最近一次结果，并提示用户要装好 ntfy。
- info 级不单独推送。每天在设定的悉尼时间推一条摘要，App 设置里提供摘要时间的选择。

## 6. 安全规则（每次提交前自查）

1. **只读**：全部代码里只允许一个 POST，就是 `POST /devices`；不能有 PUT、DELETE、PATCH。要写一个单元测试或 grep 脚本来断言这一点。
2. **网络**：只用 https，不加任何 ATS 例外，不写死任何地址；示例地址用 `mac-mini.xxxx.ts.net` 这类占位符。
3. **密钥**：App 不新增交易密钥（OKX 只读密钥照旧，见第 0 节），不保存 relay 的 HMAC 密钥，不保存私有 AI 的管理员密码。设备令牌只放钥匙串。
4. **本地存储**：含金额的缓存不要放 UserDefaults，`缓存.swift` 要迁到文件里，加 `completeUntilFirstUserAuthentication` 文件保护。日志里不打印令牌和金额。
5. **logo.dev 的 key**：移到不进 Git 的配置文件里；没有配置时显示首字母图标。不要把这个 key 复制到新文件里。
6. **改机器名的影响**：网站计划要求机器名不能透露用途，现在手册里是 `quant-mini`。如果用户改名，relay 地址就变了，钥匙串里的令牌是按地址存的，需要重新配对。App 要能给出清楚的提示。

## 7. 测试与验收

- **包测试**（Swift Testing）：
  - 每个投影都要有手写的样例 JSON，覆盖完整、`available: false`、缺字段、未知字段四种情况；
  - cursor 翻页（`has_more`）；
  - Python 时间格式解析；
  - URL 校验；
  - HMAC 测试向量；
  - "只有一个 POST"的断言。
- **保留并迁移现有测试**：`PortSightTests/ServerTests.swift`、`PortfolioDemoTests.swift`。
- **手动验收**（Mac mini 装好以后由用户操作）：
  - 配对成功；
  - 服务器页显示 4 块磁盘；
  - 制造一条 warning 告警，5 到 10 分钟内收到推送，锁屏上看不到金额；
  - 断开 Wi-Fi 后显示缓存数据和数据过期提示；
  - 在中国通过 VPN + Tailscale 实测一次连接和推送。
- **不需要用户的步骤**：编译、模拟器运行、单元测试，开发者可以自己跑；推送用户本人确认。

## 8. 和另外两部分的关系

- **Mac 版（PortsightMac）**：依赖本对话做的 PortSightKit，两边模型和客户端一致。Mac 先用 `apns_token: ""` 配对，不用 APNs；原因是 relay 的 APNs topic 只有一个，见 Mac 计划。
- **网站（coffeeheart-site）**：只放一个"我的服务器（仅本人设备）"链接和一个 Healthchecks 状态徽章，和 App 没有数据往来。

## 9. 共享包 API 变更登记（Mac 对话在此追加）

- （空）
