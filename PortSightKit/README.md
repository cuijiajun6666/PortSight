# PortSightKit

Shared, UI-free code for the PortSight iOS app (`../PortSight`) and the Mac app (`../PortsightMac`): models, view models, the OKX / moomoo / relay clients, the cache, chart data and the demo fixtures. Each app keeps its own SwiftUI pages and links this package as a local dependency.

- `Models`, `ViewModels`, `Networking`, `Persistence`: the former per-app `Core` code.
- `Server`: relay models, `ServerStore` (Tailscale HTTPS only, the single allowed `POST /devices`), Keychain helpers. Push tokens come from each app through `PushTokenProvider`.
- `Demo`: fictional data, including `DemoTerminalData` for the terminal sections (trading lines, alerts, cloud, AI, remote) and `ServerSample`.

Demo mode (`DemoPortfolioData.enabled`) is on: nothing in the package opens a connection.

Tests: `xcodebuild test -scheme PortSightKit -destination 'platform=macOS'`.
