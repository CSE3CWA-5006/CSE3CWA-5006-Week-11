#!/usr/bin/env bash
set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 3: Package the local Smart City IoT project for upload.
#
# This script creates:
#   ../deployment/iot_app_package.tar.gz
#
# The package includes:
#   - public frontend files
#   - Node.js backend server
#   - SQLite database file if it exists
#   - import script and README
#
# The package excludes:
#   - .git
#   - node_modules
#   - Python virtual environment
#   - temporary SQLite WAL/SHM files
#   - local server pid/url files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WEEK11_DIR="$(cd "$PAGE_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
mkdir -p "$DEPLOY_DIR"

IOT_SOURCE_DIR="${IOT_SOURCE_DIR:-"$WEEK11_DIR/IoT"}"
PACKAGE_PATH="$DEPLOY_DIR/iot_app_package.tar.gz"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 3: Package local app"
echo "============================================================"
echo "IoT source directory: $IOT_SOURCE_DIR"
echo "Package output      : $PACKAGE_PATH"
echo

if [ ! -d "$IOT_SOURCE_DIR" ]; then
  echo "ERROR: IoT source directory was not found."
  echo
  echo "Set IOT_SOURCE_DIR manually if your project is somewhere else."
  echo "Example:"
  echo "  IOT_SOURCE_DIR=\"/mnt/e/trycli/IoT\" ./03_package_iot_app.sh"
  exit 1
fi

if [ ! -f "$IOT_SOURCE_DIR/server/server.mjs" ]; then
  echo "ERROR: server/server.mjs was not found. This does not look like the IoT project."
  exit 1
fi

if [ ! -f "$IOT_SOURCE_DIR/public/index.html" ]; then
  echo "ERROR: public/index.html was not found. This does not look like the IoT project."
  exit 1
fi

if [ -f "$IOT_SOURCE_DIR/data/smart_city_iot.sqlite" ]; then
  echo "SQLite database found:"
  ls -lh "$IOT_SOURCE_DIR/data/smart_city_iot.sqlite"
else
  echo "WARNING: SQLite database was not found in data/smart_city_iot.sqlite."
  echo "The app can still be packaged, but the server will not start until the database is created."
  echo "For this lab, use the prepared database unless the lecturer asks you to reimport data."
fi
echo

echo "Creating compressed package..."
rm -f "$PACKAGE_PATH"
tar \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='.venv' \
  --exclude='data/*.pid' \
  --exclude='data/*.url' \
  --exclude='data/*.sqlite-wal' \
  --exclude='data/*.sqlite-shm' \
  -czf "$PACKAGE_PATH" \
  -C "$IOT_SOURCE_DIR" .

echo
echo "Package created:"
ls -lh "$PACKAGE_PATH"
echo
echo "Next step:"
echo "  KEY_FILE=\"/mnt/e/trycli/verified_cli/deployment/week11-verified-sunlit.pem\" ./04_upload_and_install_iot_app.sh"
