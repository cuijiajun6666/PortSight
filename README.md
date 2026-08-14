# PortSight

PortSight is a unified portfolio project with a SwiftUI client and a Python/FastAPI backend.

## Repository layout

```text
PortSight/
├── frontend/   # iOS/macOS SwiftUI app and Xcode project
└── backend/    # FastAPI service and deployment scripts
```

## Frontend

Open `frontend/PortSight.xcodeproj` in Xcode. The OKX credentials are intentionally not stored in Git. For local development, add these environment variables to the active Xcode scheme:

- `OKX_API_KEY`
- `OKX_SECRET_KEY`
- `OKX_PASSPHRASE`

The app continues to read its backend URL from `BackendConfig.swift` and allows a saved override through `UserDefaults`.

## Backend

See [`backend/README.md`](backend/README.md) for local setup, Ubuntu deployment, and runtime-data instructions.

