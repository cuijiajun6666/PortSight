# PortSight Backend

FastAPI backend for PortSight, using Moomoo OpenD as the local trading and market data gateway.

## Server Variables

Use the current server public IP wherever you see `YOUR_SERVER_IP`.

```text
YOUR_SERVER_IP
```

Temporary backend URL:

```text
http://YOUR_SERVER_IP:8000
```

## First Deploy On Ubuntu

SSH into the server:

```bash
ssh root@YOUR_SERVER_IP
```

Run the bootstrap command:

```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://YOUR_SERVER_IP:8000 bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/bootstrap_ubuntu.sh)"
```

If this server should push runtime JSON data back to GitHub, pass a fine-grained token with `Contents: Read and write` permission for this repo:

```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://YOUR_SERVER_IP:8000 GITHUB_TOKEN=YOUR_GITHUB_TOKEN bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/bootstrap_ubuntu.sh)"
```

Replace these two parts before running it:

```text
YOUR_SERVER_IP      -> the current server IP, for example 45.63.31.248
YOUR_GITHUB_TOKEN   -> your GitHub token, usually starts with github_pat_
```

Example shape:

```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://45.63.31.248:8000 GITHUB_TOKEN=github_pat_REPLACE_WITH_YOURS bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/bootstrap_ubuntu.sh)"
```

Do not commit the real token into this repo. Only paste it into the SSH terminal command on the server.

After bootstrap, confirm the server remote uses the token:

```bash
cd /opt/moomoo-backend/app
git remote -v
```

It should look like this. Do not share the full output if it contains the real token:

```text
https://github_pat_***@github.com/cuijiajun6666/PortSight-Backend.git
```

If you omit `BACKEND_PUBLIC_URL`, the deploy script will try to detect the server public IP automatically.

The script installs system dependencies, clones this repo to `/opt/moomoo-backend/app`, creates `/opt/moomoo-backend/data`, installs Python packages, creates a systemd service, opens port `8000`, and starts the backend.

It also installs the daily runtime JSON push timer by default. To skip that timer:

```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://YOUR_SERVER_IP:8000 INSTALL_RUNTIME_DATA_PUSH_TIMER=0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/bootstrap_ubuntu.sh)"
```

To deploy the backend and then immediately install/start OpenD for first login, add `INSTALL_OPEND=1`:

```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://YOUR_SERVER_IP:8000 INSTALL_OPEND=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/bootstrap_ubuntu.sh)"
```

Combined one-line deploy with OpenD and GitHub runtime data push enabled:

```bash
REPO_URL=https://github.com/cuijiajun6666/PortSight-Backend.git BACKEND_PUBLIC_URL=http://YOUR_SERVER_IP:8000 INSTALL_OPEND=1 GITHUB_TOKEN=YOUR_GITHUB_TOKEN bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/bootstrap_ubuntu.sh)"
```

## Install OpenD On Ubuntu

After deploying the backend, install and start moomoo OpenD on the same server:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cuijiajun6666/PortSight-Backend/main/deploy/install_opend_ubuntu.sh)"
```

The script downloads the latest Ubuntu OpenD package from moomoo, extracts it under `/opt/moomoo-opend`, asks for your moomoo account and password in the SSH terminal, creates a `moomoo-opend` systemd service, and starts OpenD for first login.

If moomoo asks for device verification or 2FA, confirm it in the moomoo app. After first login succeeds, type `exit` at the OpenD `>>>` prompt. The script will then restart OpenD in the background and run verification.

Manual OpenD restart:

```bash
systemctl restart moomoo-opend
systemctl status moomoo-opend --no-pager
```

Then restart the backend:

```bash
systemctl restart moomoo-backend
```

Run server verification:

```bash
bash /opt/moomoo-backend/app/deploy/verify_server.sh
```

Sync tracked asset snapshot history into the server runtime data directory:

```bash
cd /opt/moomoo-backend/app
git pull
bash deploy/sync_asset_snapshots.sh
systemctl restart moomoo-backend
```

Push tracked runtime JSON data back to GitHub:

```bash
bash /opt/moomoo-backend/app/deploy/push_runtime_data.sh
```

Install the daily runtime JSON push timer:

```bash
bash /opt/moomoo-backend/app/deploy/install_runtime_data_push_timer.sh
```

The timer runs daily at `22:30 UTC`, after the usual US market close snapshot job.

## Advisor

The advisor is a rule-based portfolio analysis engine for medium/long-term holding decisions. It does not place orders.

It uses cached historical K lines and owner-plate data from moomoo:

```text
/opt/moomoo-backend/data/klines/day
/opt/moomoo-backend/data/klines/week
/opt/moomoo-backend/data/klines/month
/opt/moomoo-backend/data/advisor_owner_plates.json
/opt/moomoo-backend/data/advisor_valuations.json
/opt/moomoo-backend/data/advisor_financials.json
/opt/moomoo-backend/data/advisor_earnings_moves.json
/opt/moomoo-backend/data/advisor_company_profiles.json
/opt/moomoo-backend/data/advisor_operational_efficiency.json
```

Daily, weekly, and monthly K lines are requested separately from moomoo. Moomoo does not count different K-line periods for the same symbol as separate historical K-line quota usage, but each first-page request still counts toward the per-30-second request rate. The backend caches the result locally and refreshes after market close.

Owner-plate data comes from `get_owner_plate`. It is cached locally and refreshed at most daily by default.

Valuation data comes from `get_valuation_detail`. It is cached locally and refreshed at most daily by default.

Financial statement data comes from `get_financials_statements`. It is cached locally and refreshed at most daily by default.

Earnings-event price behavior comes from `get_financials_earnings_price_move` and `get_financials_earnings_price_history`. It is cached locally and refreshed at most daily by default.

Company profile and operational efficiency data come from `get_company_profile` and `get_company_operational_efficiency`. Profile data is refreshed weekly by default; operational efficiency is refreshed daily by default.

Advisor endpoints:

```bash
curl http://127.0.0.1:8000/advisor/suggestions
curl "http://127.0.0.1:8000/advisor/suggestions?refresh=true"
curl "http://127.0.0.1:8000/advisor/symbol?symbol=US.SIDU"
curl -X POST "http://127.0.0.1:8000/advisor/sync_klines"
curl -X POST "http://127.0.0.1:8000/advisor/sync_profiles"
curl -X POST "http://127.0.0.1:8000/advisor/refresh"
curl -X POST "http://127.0.0.1:8000/advisor/training_samples/record"
curl -X POST "http://127.0.0.1:8000/advisor/training_samples/update_targets"
curl "http://127.0.0.1:8000/advisor/training_samples?limit=50"
```

The backend also runs an advisor refresh job on weekdays at `16:25 America/New_York`, after the market close snapshot.

Tracked advisor runtime config:

```text
data/advisor_state.json
data/advisor_symbol_meta.json
data/advisor_training_samples.json
```

Ignored advisor cache:

```text
data/klines/
data/advisor_report.json
```

## Backend Service Commands

Check service status:

```bash
systemctl status moomoo-backend --no-pager
```

Watch logs:

```bash
journalctl -u moomoo-backend -f
```

Watch OpenD logs:

```bash
journalctl -u moomoo-opend -f
```

Restart backend:

```bash
systemctl restart moomoo-backend
```

Update backend after pushing code:

```bash
git config --global --add safe.directory /opt/moomoo-backend/app
cd /opt/moomoo-backend/app
git pull
systemctl restart moomoo-backend
```

## OpenD

Moomoo OpenD must run on the server too. The backend expects OpenD at:

```text
127.0.0.1:11111
```

Do not expose OpenD port `11111` to the public internet.

## Runtime Data

Runtime data directory on the server:

```text
/opt/moomoo-backend/data
```

Tracked asset history:

```text
data/asset_snapshots.json
```

Ignored runtime cache:

```text
data/market_intraday_cache.json
```
