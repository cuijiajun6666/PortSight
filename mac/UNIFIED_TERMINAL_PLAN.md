
# PortsightMac（macOS）综合终端：开发计划

> 这份计划写给接手开发 Mac 版的 AI 对话，开发者看不到之前的讨论，按本文执行即可。
> 建议存为 `/Users/chriscui/Desktop/Xcode/PortsightMac/UNIFIED_TERMINAL_PLAN.md`。
> 配套的另外两份计划：
> - iOS：`/Users/chriscui/Desktop/Xcode/PortSight/UNIFIED_TERMINAL_PLAN.md`
> - 网站：`/Users/chriscui/Documents/GitHub/coffeeheart-site/SERVER_ENTRY_PLAN.md`
>
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

Mac 版和 iOS 版是同一个"个人终端"，只读。功能范围和 iOS 一致：

- 资产与持仓
- 量化策略的表现，以及模拟盘或实盘状态
- 告警
- Mac mini 服务器状态
- 私有 AI 服务器状态
- 远程桌面、Immich、AI 控制台的入口

Mac 版另外要做两件事：

- 用大窗口做多栏总览；
- 加菜单栏常驻图标（MenuBarExtra）。

用户真实可投资金约 20–30 万美元。股票模拟盘的名义资金是 100 万美元，所以模拟盘只显示百分比，不和真实账户的金额相加。

**不做的事（硬规则）**：
- 不下单、不撤单；
- 不改风控；
- 不重启交易进程；
- 不实现远程桌面协议；
- 不新增任何交易所或券商的**交易**密钥。OKX 只读密钥照旧放在设备钥匙串里（见第 0 节）。

## 2. 现状（2026-10-30 只读侦察）

**工程与构建**
- 工程在 `/Users/chriscui/Desktop/Xcode/PortsightMac`，SwiftUI + SwiftData。Git 里只有一次 `85e745c Initial Commit`。
- 开工前先问用户要不要提交现有改动。没有用户同意，不要提交，也不要推送。
- 最低系统 macOS 27.0，用 Xcode 27.1 构建，Swift 5。包标识符是 `-66.PortsightMac`，开头是横杠，请用户确认。
- 已开沙盒和加固运行时（Hardened Runtime）。
  - **没有 entitlements 文件，也没开"出站网络"**（`ENABLE_OUTGOING_NETWORK_CONNECTIONS` 或 `com.apple.security.network.client`），沙盒会拦掉所有请求。
- README 第 3 行写着：编译还被 Icon Composer 图标导出卡住，整个 App 没有完整编译通过，见 `Docs/Validation/*.md`。**这个要先解决。**

**界面**
- 入口 `PortsightMac/PortsightMacApp.swift` 只有一个 `WindowGroup("PortSight")`：最小 1060×720，默认 1480×980，SwiftData 只放在内存里。
- 没有 MenuBarExtra，也没有 WidgetKit。
- 左侧是图标栏，加原生工具栏和"全部 / 个人 / 量化"账户切换器。
- 共 7 个页面，定义在 `App/Navigation/DesktopDestinations.swift`：资产总览、全部持仓、市场行情、订单记录、组合分析、量化策略、账户动态。
- 右侧有一个 310pt 的通知面板（`App/Layout/DesktopTrailingPanel.swift`）。
- 代码目录：`App/`、`Core/`（Demo、Models、Networking、ViewModels、Persistence）、`Shared/`、`Features/`。

**数据：目前完全离线演示**
- `Core/Demo/DemoPortfolioData.swift` 里写死了 `enabled = true`，启动时注册 `DemoOfflineProtocol`。
- **`Core/Networking/BackendConfig.swift` 第 13 行的默认地址还是旧的公网明文 `http://45.63.31.248:8000`**，不带协议的输入会被补成 `http://`。这是 moomoo 旧后端的地址，**按第 0 节原样保留，不要改**。它是公网明文 HTTP，只在设置里标一个"不加密"提示；以后要不要搬到 Tailscale，由用户另定。
- 老 moomoo 后端的接口（account、positions、quote、订单、advisor）都是不带认证的 GET。
- `Core/Networking/OKXClient.swift` 有签名私有接口，但没有任何调用方，也没有硬编码密钥。
- `Shared/Logos/CompanyLogo.swift` 写死了 logo.dev 的 key（不要复制）。
- 设置页里的"后端地址"只是本地备忘，不会真的拿去连接。

**和 iOS 版的关系**
- Mac 版是从 iOS 复制来的，没有服务器模块。
- 有 13 个文件和 iOS 完全相同，包括 AccountResponse、AssetViewModel、CompanyLogo、DemoPortfolioData、OKXClient、OKXModel、各 ViewModel、PortfolioAsset。
- 有差异的文件：AdvisorViewModel、AssetSnapshot、ContentView、BackendConfig 等。

## 3. 架构

### 3.1 共享包 PortSightKit（由 iOS 对话创建）

- 位置：`/Users/chriscui/Desktop/Xcode/PortSightKit`。Mac 工程以本地包方式引用，支持 macOS 27。
- 模块：
  - `PortSightCore`：relay 模型、`RelayClient`、钥匙串、新鲜度与时间解析、URL 校验、HMAC 工具；
  - `PortSightMarket`：OKX 公共行情，不带密钥；
  - `PortSightDemo`：演示数据。
- **先确认包是否已经存在。**
  - 已存在：直接引用，然后删掉 Mac 工程里那 13 个重复文件，改用包里的代码。
  - 不存在：先只做本计划里不依赖包的部分（P0 第 1–3 项）。不要自己另建一个同名包。
- Mac 对话**只往包里新增文件**，例如 `#if os(macOS)` 的辅助代码，不改已有的公开 API。要改 API，登记到 iOS 计划第 9 节。改完包以后，两边都要跑包的测试。
- 推送令牌通过协议 `PushTokenProvider` 注入，Mac 用 `NSApplicationDelegate` 实现。

### 3.2 数据源：Mac mini 上的 relay（只读，只走 Tailscale）

**连接方式**
- 地址：`https://<机器名>.<tailnet>.ts.net`，不带端口。tailscale serve 把 443 转到 `127.0.0.1:8765`。
- 不用公网 IP，不用 HTTP，不用 Funnel。

**配对**
1. 用户在 Mac mini 上运行 `python3 -m quant_system.relay pair --state sessions/portsight`，拿到一个一次性码，5 分钟有效。
2. App 发 `POST /devices`，body 为 `{"pairing_code", "apns_token": "", "digest_hour", "digest_minute"}`，返回 `{"device_token"}`。
3. 之后所有 GET 都带 `Authorization: Bearer <device_token>`。
4. 令牌存在钥匙串（GenericPassword）：service 是 `PortSight.relay`，account 是 relay 的 origin。沙盒下用本 App 自己的钥匙串即可，不需要和 iOS 共享。
- Mac 是独立的设备，要单独配对，拿自己的令牌。

**端点**（和 iOS 完全一致，字段详见 iOS 计划第 3.2 节）

| 端点 | 用途 |
|---|---|
| `GET /host` | 服务器状态，每 60 秒刷新 |
| `GET /alerts?cursor=<seq>` | 增量告警，返回 `{events, has_more, next_cursor}`，每页最多 500 条；cursor 要持久化 |
| `GET /status[?line=stock\|crypto\|account_risk]` | 线路状态，每 5 分钟刷新 |
| `GET /account[?line=…]` | 资产与持仓，每 5 分钟刷新 |
| `GET /reports/latest?type=daily\|weekly\|monthly[&line=…]` | 复盘报告 |
| `GET /advice?symbols=…`（最多 50 个） | 模型卡片 |

- 所有投影都可能返回 `available: false`，界面要显示"尚未接入"，不能报错。
- 字段全部按可选处理。要显示 `as_of` 和数据有多旧，因为 relay 每 5 分钟收集一次，数据最多可能晚约 10 分钟。

**host 里 Mac 版重点展示的字段**
- `summary`
- `host.load`、`memory.pressure`、`thermal.cpu_temp_c`（可能为 null，要装 macmon 才有）、`power`
- `disks`：internal = 内置盘，main = 三星 T7（主盘），backup = 备份，photos = 照片
- `launchd.jobs`
- `heartbeats`（runner、sleeve、collector）
- `queue.heavy_lock`、`heavy_pause`、`stop_files`
- `collector_health`、`deadman`、`alerts_active`
- `history`：只有 24 小时的 load5 和 mem_free_pct

### 3.3 推送：Mac 暂时不用 APNs

- relay 的 APNs topic 和环境全局各只能设一个（`PORTSIGHT_APNS_TOPIC/ENV`）。Mac 的 Bundle ID 不同，苹果会返回 DeviceTokenNotForTopic，relay 随即清掉这台设备的推送令牌。
- **所以 Mac 用 `apns_token: ""` 配对。** App 运行时轮询 `/alerts`，遇到新的 warning 或 critical 就发本地通知（UNUserNotificationCenter）。
- 本地通知的文字规则和 relay 一致：只写类别和时间，不写金额、持仓、detail。
- 要真正支持 Mac 的 APNs，**待 quant relay 提供**：devices 表按设备记录 topic 和环境。

### 3.4 待接口方提供（不要自己编端点）

**待 quant relay 提供**
1. 资产数据源：
   - 三条线的 `SEND_APPROVED` 都没打开；
   - `account.crypto` 没有生产者；
   - OKX、IBKR、moomoo、Hyperliquid 的只读余额不经过 relay，需要新增只读账户投影。投影名称以 relay 为准。
2. `advice`、`report_monthly` 没有生产者。
3. 设备列表和吊销接口。现在令牌不会过期，App 断开只能删本地令牌。
4. 私有 AI 的心跳还没接进 host_status。
5. 长期净值曲线和磁盘、网络的历史序列。
6. Mac 推送所需的按设备 topic 和环境。

**待 private-ai-server 提供**
- 给 App 用的只读令牌。现在的状态接口都要管理员 Basic 认证，**App 不能存管理员密码**。在这之前只放 AI 控制台的链接。

## 4. 界面与功能（按优先级）

### P0：能编译、安全、连得上

1. 解决图标导出导致的编译卡点，见 `Docs/Validation/`。
2. 加 entitlements：开沙盒出站网络（`com.apple.security.network.client`）。不开入站，不加其他权限。
3. `BackendConfig` 改成和 iOS 一样：
   - 没有内置地址；
   - 只接受 https 的 origin；
   - 明文地址直接忽略；
   - 不自动补 `http://`。

   **例外**：moomoo 后端的连接方式按第 0 节原样保留。上面这几条只用于新增的 relay 连接，moomoo 的地址和协议不在改动范围内。
4. 演示模式改成设置里的开关，默认关闭。
5. 接入 PortSightKit，删掉重复文件。

### P1：服务器页（新增，放在左侧图标栏）

- 多栏布局：
  - 总览卡（状态、告警数、数据多旧）；
  - 负载、内存、温度、电源，配 24 小时曲线；
  - 4 块磁盘；
  - 心跳表（可排序）；
  - launchd 任务表；
  - 重任务队列；
  - deadman。
- 数据过期时显示红色横幅。
- 右侧通知面板改成显示真实告警流，按 severity 着色，按 category 筛选。

### P1：菜单栏 MenuBarExtra

- 图标颜色跟 `summary.state` 走：ok、warning、critical 各一种。
- 下拉菜单内容：
  - 活跃告警的前 5 条；
  - 心跳出问题的数量；
  - 上次更新时间；
  - "打开主窗口"；
  - 远程桌面、Immich、AI 控制台三个快捷入口。
- **默认显示总资产和今日盈亏**；打开"隐藏金额"后改成只显示状态。
- 关掉主窗口后，菜单栏继续轮询，频率最多每 60 秒一次。

### P0/P1：资产页（P0，见第 0.2 节）和量化策略页（P1）

- **量化策略页**：显示 stock、crypto、account_risk 三条线的模式（模拟盘 / 实盘 / 影子）、运行结果、各阶段状态、`lines.scale`，以及日报和周报的指标与 `points` 曲线。
- **资产总览和全部持仓**：真实资产来自 moomoo 后端和 OKX 直连，模拟盘来自 relay 的 `/account?line=…`，两者分区显示，不合计。"全部 / 个人 / 量化"先按 sleeve 和线路来分。

### P2：入口与远程桌面

- 首选 Jump Desktop：Fluid 协议，Cloudless 直连 Tailscale 地址，Mac mini 上装 Jump Desktop Connect。`jump://` 深链的格式以官方文档为准，实现前先核对。拿不准时只打开 Jump Desktop App。
- 备用是 macOS 屏幕共享：`vnc://<机器名>`，由系统的"屏幕共享"打开。在帮助里提示：两端都是 Apple 芯片且 macOS 14 以上时，可以选"高性能"模式。
- UU 远程不放链接，只在帮助里写"应急备用，平时关闭"。
- Immich：`https://<机器名>.<tailnet>.ts.net:10000`。
- AI 控制台：`https://<机器名>.<tailnet>.ts.net:8443`，用浏览器打开，用户自己登录。

### P3：其他

- WidgetKit 桌面小组件，只显示状态和告警数。
- advice 卡片，等有生产者以后再做。
- 私有 AI 状态卡，等有只读令牌以后再做。

## 5. 安全规则

1. **只读**：全部代码里只允许一个 POST，就是 `POST /devices`。用测试或 grep 脚本来断言。
2. **网络**：只用 https，不写死任何地址；示例用 `mac-mini.xxxx.ts.net` 这类占位符。
3. **密钥**：不新增交易密钥（OKX 只读密钥照旧，见第 0 节），不保存 relay 的 HMAC 生产者密钥，不保存私有 AI 管理员密码。设备令牌只放钥匙串。
4. **本地数据**：含金额的缓存放在 App 容器的文件里，不放 UserDefaults。日志不打印令牌和金额。
5. **logo.dev 的 key**：移到不进 Git 的配置里；没有配置时显示首字母图标。
6. **机器名**：如果用户把 `quant-mini` 改成不透露用途的名字（网站计划要求这样做），relay 地址就变了，需要重新配对。App 要给出清楚的提示。

## 6. 测试与验收

- **测试**
  - 包测试由 iOS 对话维护，Mac 侧要能跑通。
  - Mac 自己的测试要覆盖：
    - 新增的 relay 连接只接受 https；moomoo 旧连接照常能用（第 0 节）；
    - 本地通知的文字里不含任何数字金额或 detail；
    - MenuBarExtra 在"隐藏金额"打开时不显示金额。
- **开发者自己能做的**：编译、运行、单元测试。
- **用户在 Mac mini 装好后实测**：
  - 配对；
  - 服务器页显示 4 块磁盘；
  - 制造一条 warning 告警，几分钟内出现本地通知；
  - 断网后显示缓存数据和过期横幅；
  - 远程桌面的两个入口都能打开。

## 7. 和另外两部分的关系

- **iOS（PortSight）**：同一个共享包，同一套接口和界面用语。iOS 负责 APNs 推送；Mac 只用本地通知，直到 relay 支持按设备记录 topic。
- **网站（coffeeheart-site）**：只有一个"我的服务器（仅本人设备）"链接和一个 Healthchecks 徽章，和 App 没有数据往来。
