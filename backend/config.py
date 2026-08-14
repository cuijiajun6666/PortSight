import os
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.getenv("MOOMOO_DATA_DIR", BASE_DIR / "data")).expanduser()
DATA_DIR.mkdir(parents=True, exist_ok=True)

HOST = os.getenv("MOOMOO_OPEND_HOST", "127.0.0.1")
PORT = int(os.getenv("MOOMOO_OPEND_PORT", "11111"))

START_DATE = os.getenv("MOOMOO_START_DATE", "2026-01-01")

BACKEND_PUBLIC_URL = os.getenv("BACKEND_PUBLIC_URL", "http://127.0.0.1:8000")
