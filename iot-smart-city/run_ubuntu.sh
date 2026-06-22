#!/usr/bin/env bash
# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="${IOT_INPUT:-}"
DB="${IOT_DB:-"$ROOT_DIR/data/smart_city_iot.sqlite"}"
PORT="${PORT:-5177}"
REIMPORT=0
SKIP_INSTALL=0
INSTALL_ONLY=0

usage() {
  cat <<'EOF'
Smart City IoT Network Monitor - Ubuntu runner

Usage:
  ./run_ubuntu.sh --input /path/to/all.csv
  ./run_ubuntu.sh --input /path/to/data-directory --reimport
  PORT=8080 ./run_ubuntu.sh --input /path/to/all.csv

Options:
  --input PATH       CSV/XLSX file or directory to import.
  --db PATH          SQLite database path. Default: ./data/smart_city_iot.sqlite
  --port PORT        Web port. Default: 5177
  --reimport         Rebuild SQLite even if the database already exists.
  --skip-install     Do not install apt or Python dependencies.
  --install-only     Install dependencies and exit.
  -h, --help         Show help.

Environment alternatives:
  IOT_INPUT=/path/to/all.csv IOT_DB=/path/to/iot.sqlite PORT=5177 ./run_ubuntu.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="${2:-}"
      shift 2
      ;;
    --db)
      DB="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --reimport)
      REIMPORT=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --install-only)
      INSTALL_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "This script needs sudo for dependency installation. Install sudo or run as root." >&2
    exit 1
  fi
}

node_major() {
  node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || echo 0
}

install_dependencies() {
  if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get was not found. Install Node.js 24, python3-venv, python3-pip, and sqlite3 manually, then rerun with --skip-install." >&2
    exit 1
  fi

  echo "Installing Ubuntu packages..."
  sudo_cmd apt-get update
  sudo_cmd apt-get install -y ca-certificates curl gnupg python3 python3-venv python3-pip sqlite3 libsqlite3-dev

  local major
  major="$(node_major)"
  if [[ "$major" -lt 24 ]]; then
    echo "Installing Node.js 24 because this app uses Node's built-in node:sqlite module..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo_cmd bash -
    sudo_cmd apt-get install -y nodejs
  fi

  major="$(node_major)"
  if [[ "$major" -lt 24 ]]; then
    echo "Node.js 24+ is required, but node reports major version $major." >&2
    exit 1
  fi
}

choose_default_input() {
  if [[ -n "$INPUT" ]]; then
    return
  fi

  local candidates=(
    "$ROOT_DIR/dataall/all.csv"
    "$ROOT_DIR/data/all.csv"
    "$ROOT_DIR/all.csv"
    "$ROOT_DIR/dataall"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -e "$candidate" ]]; then
      INPUT="$candidate"
      return
    fi
  done
}

setup_python_env() {
  local venv_dir="$ROOT_DIR/.venv"
  local python_bin="$venv_dir/bin/python"

  if [[ ! -x "$python_bin" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$venv_dir"
  fi

  echo "Installing Python packages..."
  "$python_bin" -m pip install --upgrade pip
  "$python_bin" -m pip install pandas openpyxl
}

import_database_if_needed() {
  mkdir -p "$(dirname "$DB")"

  if [[ "$REIMPORT" -eq 0 && -f "$DB" ]]; then
    echo "Using existing SQLite database: $DB"
    echo "Pass --reimport to rebuild it."
    return
  fi

  choose_default_input

  if [[ -z "$INPUT" ]]; then
    echo "No input data path was provided." >&2
    echo "Run: ./run_ubuntu.sh --input /path/to/all.csv" >&2
    exit 1
  fi

  if [[ ! -e "$INPUT" ]]; then
    echo "Input path does not exist: $INPUT" >&2
    exit 1
  fi

  echo "Importing IoT data into SQLite..."
  "$ROOT_DIR/.venv/bin/python" "$ROOT_DIR/scripts/import_iot_to_sqlite.py" \
    --input "$INPUT" \
    --output "$DB" \
    --replace
}

install_dependencies
setup_python_env

if [[ "$INSTALL_ONLY" -eq 1 ]]; then
  echo "Dependencies installed."
  exit 0
fi

import_database_if_needed

export IOT_DB="$DB"
export PORT="$PORT"

echo "Starting Smart City IoT Network Monitor..."
echo "Open: http://localhost:$PORT"
exec node --no-warnings "$ROOT_DIR/server/server.mjs"
