# Mac mini：开公网让家人在 PortSight 里看 Immich 照片（任务清单，2026-11-10）

给在 Mac mini 上做事的对话看。

## 背景

- 家人在国内，iPhone 上只开翻墙，不装 Tailscale。iOS 同一时间只能开一个 VPN，Tailscale 和翻墙 App 会互相顶掉。
- **上传不变**：家人用 PortSight 家人版把原图传到 Google Drive。Mac mini 按 FAMILY_UPLOAD.md 每 15 分钟搬走、核对，再删掉云盘里的那份。
- **查看（这次要做）**：家人直接在 PortSight 家人版里看照片。App 带着一把只读的 Immich API key，通过 Mac mini 的公网 HTTPS 地址调用 Immich 的接口（`/api/...`），不经过中转服务。家人不需要装 Immich App，也不需要 Immich 密码。
- **全家共用一个 Immich 账号「家庭」**：所有照片都导入这个账号。Immich 的人物、回忆、地图和搜索都是按账号算的，只有放在同一个账号里，全家的照片才能一起识别、一起浏览。
- **不租服务器**：先用家里宽带的公网 IP 加路由器端口转发。没有公网 IPv4 时改用 Tailscale Funnel（第 7 节）。
- PortSight 那边由另一个对话改 App。App 需要这边交出的东西写在第 5 节和第 8 节。

## 0. 边界：不要做的事

- 量化系统和中转服务（quant_system/relay）保持现状：继续只走 Tailscale，不暴露到公网，不改接口。
- 公网只开一个 HTTPS 入口，只通往 Immich。下面这些都不能直接开到公网：
  - Immich 的 2283 端口；
  - SSH、屏幕共享、SMB；
  - 中转服务。
- 不提供明文 HTTP 访问。80 端口只有在证书验证需要时才开。
- 以下内容不能出现在日志、脚本输出、文档或 git 里：
  - Drive 的 refresh_token 和 client_secret；
  - Immich API key；
  - DuckDNS token；
  - 家人密码。

## 1. 确认家里宽带有公网 IPv4（需要用户本人看路由器）

- 对比路由器 WAN 口显示的 IP 和 `curl -s https://api.ipify.org` 的结果：
  - **两者一致**：有公网 IP，继续往下做。
  - **WAN 口是 100.64–100.127.x.x，或 10.x、172.16–31.x、192.168.x**：说明运营商做了地址共享（CGNAT），端口转发不起作用。这时有两个办法：
    - 找运营商要公网 IP（部分澳洲运营商可以免费退出 CGNAT）；
    - 直接跳到第 7 节用 Funnel。
- 再确认这个 IP 是固定的还是会变，这决定要不要做第 2 节的动态域名更新。

## 2. 域名（免费）

- 默认用 DuckDNS 的免费子域名，例如 `xxx-photos.duckdns.org`。注册和拿 token 需要用户本人操作。
- Mac mini 上用 launchd 每 5 分钟更新一次 DuckDNS 记录（IP 固定的话可以不做）。
  - token 放钥匙串，或者放只有本机用户能读的文件里，不进日志。
- 用户如果有自己的域名，就改用 A 记录加动态更新，其他步骤不变。

## 3. Mac mini 上的 HTTPS 反向代理

- 用 Caddy 把 `https://<域名>` 反代到 `http://127.0.0.1:2283`（Immich 端口以实际配置为准）。
  - 用 Homebrew 安装，用 launchd 常驻，开机自动起。
  - Let's Encrypt 证书由 Caddy 自动申请和续期。
- 证书验证要求公网的 443（或 80）能打到 Caddy。如果本机 443 已经被别的服务占了（比如中转服务或 `tailscale serve`）：
  - 让 Caddy 监听别的端口；
  - 在路由器上把「公网 443」映射到这个端口；
  - 确认证书照样能申请下来。
- Caddy 只反代 Immich。
- 在 Immich 管理设置 → 服务器 → 外部域名，填 `https://<域名>`，分享链接会用到。

## 4. 路由器（需要用户本人操作）

- 在路由器里给 Mac mini 固定局域网地址（DHCP 保留）。
- 端口转发只做一条：TCP 公网 443 → Mac mini 上 Caddy 的端口。证书验证要用 80 时再加 80，其他端口一律不转。
- macOS 防火墙允许 Caddy 入站。
- Mac mini 不能休眠。

## 5. Immich 设置

- **账号**
  - 建一个普通账号「家庭」，所有家人的照片都导入这里，用强密码，密码只有用户自己知道。
  - 管理员账号单独留着，平时不用。
- **给每台家人手机一把只读 API key**
  - key 建在「家庭」账号下，一台手机一把，按手机命名，例如「妈妈的 iPhone」。手机丢了就只删那一把。
  - 只勾读取类权限：`asset.read`、`asset.view`、`asset.download`、`album.read`、`person.read`、`map.read`、`memory.read`。权限名以当前 Immich 版本的列表为准，任何写入或删除类权限都不勾。
  - key 只出现在第 8 节那段配置 JSON 里，交给用户转发。这边不留明文记录，不进日志。
- **版本**
  - 用 Immich v3.x，记下具体版本号回报。
  - App 是按这一版的接口写的，以后升级大版本之前要先告诉用户。
- **中文搜索**
  - 在管理设置 → 机器学习 → 智能搜索里，换成 Immich 文档里标为多语言（multilingual）的 CLIP 模型。
  - 换完后重跑「智能搜索」任务。
- **维护**
  - Immich 保持更新。升级前先看 release notes 里有没有破坏性变更。
  - 打开数据库自动备份。
  - 照片库所在的盘要纳入现有的备份。

## 6. Drive → Immich 入库（接在 FAMILY_UPLOAD.md 的搬运后面）

- 确认每 15 分钟一次的 rclone 搬运正常。
  - 权限是 `drive.file`，只能看到本项目建的文件。用户在网页上手动拖进云盘的文件看不到，这是预期行为。
- 搬下来的文件全部导入「家庭」账号。二选一，以 FAMILY_UPLOAD.md 现在的落地目录为准：
  - **Immich 官方命令行工具**：用一把只给上传所需权限的 key，只存在 Mac mini 本机，和手机上那几把只读 key 分开；
  - **Immich「外部图库」**：指向落地目录，所有者设成「家庭」。
- 可选：按上传的家人分别建相册，例如「妈妈上传」，以后 App 可以按人筛选。
- 只有确认导入成功（Immich 返回成功，或判定为重复）之后，才能删除本地的中转副本。云盘里那份按原流程核对后删除。
- **文件格式**
  - 文件名格式：`<拍摄时间 yyyyMMdd_HHmmss>_<资源 ID 前 8 位>_<原文件名>`。
  - 实况照片的照片和视频是两个文件、用同一个前缀，两个都要导入，Immich 会自动配成实况照片。
  - 文件元数据里的 `appProperties.taken_at` 是拍摄时间（ISO 8601），可以不读，Immich 会从 EXIF 读。
- 云盘免费空间只有 15 GB。搬运一旦停摆，云盘就会满，App 那边会提示「云盘暂时满了」。可选：搬运或入库连续失败时发一条告警，比如通过现有中转服务推送。

## 7. 备选：没有公网 IPv4 时用 Tailscale Funnel

- 用下面这条命令把 Immich 开到公网 8443 端口，常驻后台，重启后自动恢复。它不会占用中转服务的 443：

  ```bash
  tailscale funnel --bg --https=8443 2283
  ```

- 访问地址是 `https://<机器名>.<tailnet>.ts.net:8443`。
- 第一次运行时，如果提示这台机器没有 Funnel 权限，按提示到 Tailscale 后台开启。
- Funnel 的公网端口只能用 443、8443、10000。
- Funnel 有带宽上限，具体数字官方没公布。看缩略图够用，大量看原图或视频可能会慢。
- 关闭命令：`tailscale funnel --https=8443 2283 off`
- 用 Funnel 的话，第 1–4 节都不用做，第 0、5、6、8、9 节照做。

## 8. 交给 App 的配置（每台手机一份）

在现有 Drive 配置 JSON（见 Drive 直传接口约定第 2 节）里加一个 `immich` 对象，其他字段不变：

```
{"client_id": "....apps.googleusercontent.com",
 "client_secret": "...",
 "refresh_token": "1//...",
 "folders": {"妈妈": "<folder id>", "爸爸": "<folder id>"},
 "immich": {"url": "https://<域名>", "api_key": "<这台手机的只读 key>"}}
```

- `immich.url` 只写到域名（用 Funnel 的话带上 `:8443`），必须是 `https://`，末尾不要 `/`，也不要加 `/api`，App 会自己拼。
- 每台手机一份，因为每份里的 refresh_token 和 Immich key 都是这台手机专用的。
- 这段 JSON 由用户转发给家人，家人在 PortSight 设置里整段粘贴即可。

家人手机上还要做一件事：在翻墙 App 里加一条规则，确保这个地址走代理。

- 公网 IP 方案：`DOMAIN-SUFFIX,<域名>,PROXY`
- Funnel 方案：`DOMAIN-SUFFIX,ts.net,PROXY`

家人不需要装 Immich App。

## 9. 验收

1. 手机关掉 Wi-Fi 和 Tailscale，用蜂窝网络打开 `https://<域名>`：能看到 Immich 登录页，证书有效。
2. 从外网检查：只有 443（以及可能需要的 80）是开着的。中转服务从外网连不上，从 Tailscale 照常能用。
3. 用一把手机 key 从外网检查两件事：
   - 带 `x-api-key` 请求头调 `GET /api/timeline/buckets`，返回 200；
   - 调任何写入接口，例如给一张照片加收藏，返回 403，证明 key 确实只读。
   - 检查时不要把 key 写进记录。
4. 用 PortSight 家人版传三样东西：一张普通照片、一张实况照片、一个超过 100 MB 的视频。30 分钟内它们出现在「家庭」账号的时间线上，实况照片能播放，云盘里的副本已经删掉。
5. 重启 Mac mini 之后，Caddy、域名更新、搬运和入库都能自动恢复。

## 10. 做完请回报

- 最终访问地址，以及用的是公网 IP 方案还是 Funnel。
- 有没有遇到运营商地址共享（CGNAT）。
- Immich 的具体版本号。
- 手机 key 勾了哪些权限，第 9 节第 3 条的结果。
- 用的是哪个 CLIP 模型。
- 入库用的是命令行工具还是外部图库，以及每条验收的结果。
- 配置 JSON 不要贴在回报里，由用户单独转发给家人。
