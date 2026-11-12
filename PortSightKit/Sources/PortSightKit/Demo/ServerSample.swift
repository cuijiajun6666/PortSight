//
//  ServerSample.swift
//  PortSight
//
//  Synthetic GET /host document for the "查看样例" button and the decoding test: produced by
//  quant_system/monitoring/host_status.py from a made-up project tree (not any real machine).
//

import Foundation

public enum ServerSample {
    /// The sample document decoded once, for pages that show it without going through ServerStore.
    public static let host: HostStatus? = json.data(using: .utf8).flatMap { try? JSONDecoder().decode(HostStatus.self, from: $0) }

    public static let json = #"""
{
 "schema_version": 1,
 "kind": "host_status",
 "as_of": "2026-11-03T02:00:00Z",
 "generated_at": "2026-11-03T02:00:00Z",
 "available": true,
 "stale_after_minutes": 15,
 "summary": {
  "state": "warning",
  "active_alerts": 1,
  "heartbeats_ok": 6,
  "heartbeats_problem": 1
 },
 "host": {
  "hostname": "mac-mini",
  "cpu_count": 14,
  "load": {
   "m1": 3.1,
   "m5": 2.6,
   "m15": 2.2,
   "per_core_5m": 0.19
  },
  "memory": {
   "total_gb": 64.0,
   "pressure": "normal",
   "free_pct": 58,
   "swap_used_gb": 0.0,
   "swap_total_gb": 0.0
  },
  "thermal": {
   "available": true,
   "thermal_warning": null,
   "performance_warning": null,
   "cpu_speed_limit": null,
   "cpu_temp_c": 52.5,
   "gpu_temp_c": 47.8
  },
  "power": {
   "source": "AC Power",
   "kind": "ac",
   "percent": null
  },
  "boot_at": "2026-10-31T20:00:00Z",
  "uptime_hours": 54.0
 },
 "disks": {
  "internal": {
   "path": "/Users/me/quant",
   "mounted": true,
   "free_gb": 612.4,
   "total_gb": 994.7,
   "used_pct": 38.4
  },
  "main": {
   "path": "/Volumes/三星T7",
   "mounted": true,
   "free_gb": 2870.2,
   "total_gb": 4000.8,
   "used_pct": 28.3
  },
  "backup": {
   "path": "/Volumes/KINGSTON_BAK",
   "mounted": false
  },
  "photos": {
   "path": "/Volumes/照片",
   "mounted": false
  },
  "local_fallback": {
   "files": 0,
   "mb": 0.0,
   "blocked": 0
  }
 },
 "launchd": {
  "available": true,
  "jobs": {
   "com.personalquant.crypto-paper": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": null,
    "last_exit": "0",
    "state": "idle"
   },
   "com.personalquant.forward15m": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": null,
    "last_exit": "0",
    "state": "idle"
   },
   "com.personalquant.hltrades": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": 502,
    "last_exit": "0",
    "state": "running"
   },
   "com.personalquant.hoststatus": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": null,
    "last_exit": "0",
    "state": "idle"
   },
   "com.personalquant.liquidations": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": 501,
    "last_exit": "0",
    "state": "running"
   },
   "com.personalquant.okxgaps": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": null,
    "last_exit": "0",
    "state": "idle"
   },
   "com.personalquant.relay": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": 504,
    "last_exit": "0",
    "state": "running"
   },
   "com.personalquant.snapshots": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": null,
    "last_exit": "0",
    "state": "idle"
   },
   "com.personalquant.upbitlatency": {
    "group": "unregistered",
    "schedule": null,
    "daemon": null,
    "loaded": true,
    "pid": 503,
    "last_exit": "0",
    "state": "running"
   }
  }
 },
 "heartbeats": [
  {
   "name": "crypto_paper",
   "kind": "runner",
   "label": "com.personalquant.crypto-paper",
   "last_beat": "2026-11-03T01:56:00Z",
   "age_min": 4.0,
   "warn_min": 10,
   "crit_min": 120,
   "state": "ok",
   "phase": "sealed",
   "mode": "shadow",
   "stages_with_error": []
  },
  {
   "name": "stock_daily",
   "kind": "runner",
   "label": "com.personalquant.stockdaily",
   "last_beat": null,
   "age_min": null,
   "state": "not_installed"
  },
  {
   "name": "account_risk",
   "kind": "runner",
   "last_beat": null,
   "age_min": null,
   "state": "not_installed"
  },
  {
   "name": "liquidations",
   "kind": "collector",
   "label": "com.personalquant.liquidations",
   "last_beat": "2026-11-03T01:59:00Z",
   "age_min": 1.0,
   "warn_min": 15,
   "crit_min": 60,
   "state": "ok"
  },
  {
   "name": "hl_big_trades",
   "kind": "collector",
   "label": "com.personalquant.hltrades",
   "last_beat": "2026-11-03T01:58:00Z",
   "age_min": 2.0,
   "warn_min": 15,
   "crit_min": 60,
   "state": "ok"
  },
  {
   "name": "upbit_latency",
   "kind": "collector",
   "label": "com.personalquant.upbitlatency",
   "last_beat": "2026-11-03T01:59:40Z",
   "age_min": 0.3,
   "warn_min": 10,
   "crit_min": 60,
   "state": "ok"
  },
  {
   "name": "forward15m",
   "kind": "collector",
   "label": "com.personalquant.forward15m",
   "last_beat": "2026-11-03T00:50:00Z",
   "age_min": 70.0,
   "warn_min": 45,
   "crit_min": 180,
   "state": "stale"
  },
  {
   "name": "okxgaps",
   "kind": "collector",
   "label": "com.personalquant.okxgaps",
   "last_beat": "2026-11-03T01:20:00Z",
   "age_min": 40.0,
   "warn_min": 150,
   "crit_min": 360,
   "state": "ok"
  },
  {
   "name": "snapshots",
   "kind": "collector",
   "label": "com.personalquant.snapshots",
   "last_beat": "2026-11-02T23:00:00Z",
   "age_min": 180.0,
   "warn_min": 510,
   "crit_min": 780,
   "state": "ok"
  },
  {
   "name": "hyperliquid_positions",
   "kind": "collector",
   "label": "com.personal-quant.hyperliquid-positions",
   "last_beat": null,
   "age_min": null,
   "warn_min": 1800,
   "crit_min": 3240,
   "state": "not_installed",
   "status": null
  },
  {
   "name": "hyperliquid_fills",
   "kind": "collector",
   "label": "com.personal-quant.hyperliquid-fills",
   "last_beat": null,
   "age_min": null,
   "warn_min": 1800,
   "crit_min": 3240,
   "state": "not_installed",
   "status": null
  },
  {
   "name": "smart_money",
   "kind": "collector",
   "label": "com.personal-quant.smart-money-daily",
   "last_beat": null,
   "age_min": null,
   "warn_min": 1800,
   "crit_min": 3240,
   "state": "not_installed",
   "status": null
  }
 ],
 "queue": {
  "heavy_lock": {
   "owner": "crypto-cadence",
   "pid": 51453,
   "alive": true,
   "since": "2026-11-02T23:00:00Z",
   "held_hours": 3.0
  },
  "heavy_pause": null,
  "stop_files": [
   {
    "name": "STOP_CRYPTO_EXPAND",
    "where": "research_lab/queue",
    "since": "2026-10-30T02:47:51Z"
   }
  ]
 },
 "collector_health": {
  "available": true,
  "generated_at": "2026-11-02T12:00:00Z",
  "age_min": 840.0,
  "alerts": [
   "okx_calendar: 2 runs in 24 h, expected about 4"
  ],
  "alert_count": 1
 },
 "deadman": {
  "enabled": true,
  "last_ok": "2026-11-03T01:57:00Z",
  "last_attempt": null,
  "consecutive_failures": 0,
  "last_result": "http 200"
 },
 "alerts_active": [
  {
   "key": "hb:forward15m",
   "severity": "warning",
   "title": "采集器 forward15m 70 分钟没有心跳",
   "since": "2026-11-03T01:40:00Z"
  }
 ],
 "alerts_recent": [
  {
   "id": "host:hb:forward15m:20261103T014000Z",
   "source": "host-status",
   "category": "ops",
   "severity": "warning",
   "title": "采集器 forward15m 55 分钟没有心跳",
   "detail": {
    "age_min": 55.0
   },
   "at": "2026-11-03T01:45:00+00:00"
  }
 ],
 "history": [
  [
   "2026-11-03T01:00:00Z",
   2.8,
   60
  ],
  [
   "2026-11-03T01:05:00Z",
   2.4,
   59
  ],
  [
   "2026-11-03T01:10:00Z",
   2.0,
   58
  ],
  [
   "2026-11-03T01:15:00Z",
   3.6,
   57
  ],
  [
   "2026-11-03T01:20:00Z",
   3.2,
   56
  ],
  [
   "2026-11-03T01:25:00Z",
   2.8,
   55
  ],
  [
   "2026-11-03T01:30:00Z",
   2.4,
   61
  ],
  [
   "2026-11-03T01:35:00Z",
   2.0,
   60
  ],
  [
   "2026-11-03T01:40:00Z",
   3.6,
   59
  ],
  [
   "2026-11-03T01:45:00Z",
   3.2,
   58
  ],
  [
   "2026-11-03T01:50:00Z",
   2.8,
   57
  ],
  [
   "2026-11-03T01:55:00Z",
   2.4,
   56
  ],
  [
   "2026-11-03T02:00:00Z",
   2.6,
   58
  ]
 ],
 "relay_age_seconds": 30,
 "stale": false
}
"""#
}
