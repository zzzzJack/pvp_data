#!/usr/bin/env bash
set -euo pipefail

# One-click import for production data on WSL2 Ubuntu
# - Removes historical .done markers
# - Creates venv and installs dependencies
# - Truncates match_records via SQLAlchemy (no docker-compose required)
# - Imports all JSONL under IMPORT_DIR with server filtering and source_type mapping

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Configurable envs (with sensible defaults)
: "${IMPORT_DIR:=data_logs}"
: "${EXCLUDE_SERVERS:=9000}"
: "${DEFAULT_GOLD_LEAGUE_METRIC:=winrate}"
: "${DEFAULT_SEASON_METRIC:=winrate}"

# DB envs should match backend/app/database.py defaults if not provided
: "${POSTGRES_USER:=app}"
: "${POSTGRES_PASSWORD:=app}"
# Prefer UNIX socket on WSL if available
if [ -z "${POSTGRES_HOST:-}" ]; then
  if [ -S /var/run/postgresql/.s.PGSQL.5432 ] || [ -d /var/run/postgresql ]; then
    export POSTGRES_HOST="/var/run/postgresql"
  else
    export POSTGRES_HOST="localhost"
  fi
fi
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_DB:=pvp}"
# Do NOT auto start DB in this environment (explicitly disabled per user)
: "${AUTO_START_DB:=0}"

echo "[1/5] Ensuring Python venv and dependencies..."
# Pick a Python interpreter
if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo "ERROR: No python found. Please install Python 3."
  exit 1
fi

# Try to create venv; if failed or no activate file, fallback to system python
USE_VENV=0
if [ ! -d .venv ]; then
  if "$PY" -m venv .venv >/dev/null 2>&1; then
    :
  else
    echo "WARN: Failed to create venv. Will use system Python."
  fi
fi
if [ -f .venv/bin/activate ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
  PY=python
  USE_VENV=1
else
  echo "WARN: .venv/bin/activate not found. Using system Python ($PY)."
fi

"$PY" -m pip install -q -r requirements.txt

echo "[2/7] Cleaning previous import markers (*.done) under '$IMPORT_DIR'..."
if [ -d "$IMPORT_DIR" ]; then
  find "$IMPORT_DIR" -type f -name "*.done" -delete || true
else
  echo "WARN: IMPORT_DIR '$IMPORT_DIR' does not exist."
fi

echo "[3/7] Ensuring PostgreSQL TCP auth and app role/database (Scheme A)..."
PG_HBA=
for CAND in /etc/postgresql/*/main/pg_hba.conf; do
  if [ -f "$CAND" ]; then PG_HBA="$CAND"; fi
done
if [ -z "$PG_HBA" ]; then
  echo "WARN: pg_hba.conf not found under /etc/postgresql/*/main/. Skipping pg_hba edits."
else
  echo " - Using pg_hba.conf: $PG_HBA"
  if ! grep -E "^[[:space:]]*host[[:space:]]+all[[:space:]]+app[[:space:]]+127\.0\.0\.1/32[[:space:]]+md5" -q "$PG_HBA"; then
    echo " - Adding TCP md5 rule for user 'app' on 127.0.0.1/32"
    sudo cp "$PG_HBA" "$PG_HBA.bak" || true
    sudo sed -i '1ihost    all             app             127.0.0.1/32            md5' "$PG_HBA"
    sudo service postgresql restart || sudo systemctl restart postgresql || true
  else
    echo " - TCP md5 rule already present."
  fi
fi

echo " - Ensuring role/database exist..."
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='app'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE app WITH LOGIN PASSWORD 'app';" || true
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='pvp'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE pvp OWNER app;" || true

# Force TCP connection for the rest of the script per Scheme A
export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT=5432
export POSTGRES_USER=app
export POSTGRES_PASSWORD=app
export POSTGRES_DB=pvp

echo "[4/7] Waiting for database to be ready..."
"$PY" - <<'PY'
import os, time
from backend.app.database import engine

timeout = int(os.environ.get('DB_WAIT_TIMEOUT_SEC', '90'))
deadline = time.time() + timeout
last_err = None
while time.time() < deadline:
    try:
        with engine.connect() as conn:
            conn.exec_driver_sql('SELECT 1;')
        print('DB is ready.')
        break
    except Exception as e:
        last_err = e
        time.sleep(1)
else:
    print("Database connection failed. Please ensure your Postgres is running and envs are set correctly:")
    print(" - POSTGRES_HOST=unix socket path like /var/run/postgresql or 'localhost'")
    print(" - POSTGRES_PORT=5432 (ignored when using unix socket)")
    print(" - POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_DB")
    raise SystemExit(f"ERROR: DB not ready within {timeout}s: {last_err}")
PY

echo "[5/7] Truncating table 'match_records'..."
"$PY" - <<'PY'
from backend.app.database import engine
with engine.connect() as conn:
    conn.exec_driver_sql('TRUNCATE TABLE match_records;')
    conn.commit()
print('Truncated match_records.')
PY

echo "[6/7] Importing JSONL from '$IMPORT_DIR' (exclude servers: $EXCLUDE_SERVERS)..."
"$PY" -m backend.app.ingestion --logs_dir "$IMPORT_DIR"

echo "[7/7] Checking total row count..."
"$PY" - <<'PY'
from sqlalchemy import text
from backend.app.database import SessionLocal
with SessionLocal() as db:
    cnt = db.execute(text("SELECT COUNT(*) FROM match_records;"))
    # SQLAlchemy 2.0: scalar_one_or_none()/scalar()
    try:
        total = cnt.scalar_one()
    except Exception:
        total = cnt.scalar()
    print("Total rows:", total)
PY

echo "Done."


