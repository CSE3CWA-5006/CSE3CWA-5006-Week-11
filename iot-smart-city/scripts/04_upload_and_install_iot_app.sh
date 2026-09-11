#!/usr/bin/env bash
set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 4: Upload the packaged IoT app to EC2 and install it.
#
# This script:
#   - reads the EC2 public IP created by 02_create_iot_ec2.sh
#   - uploads iot_app_package.tar.gz by scp
#   - installs Node.js 24, SQLite and Nginx on Ubuntu
#   - extracts the app to /opt/smart-city-iot
#   - creates a systemd service for the Node backend
#   - configures Nginx as the public HTTP entry point

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
ENV_FILE="$DEPLOY_DIR/aws_iot_instance.env"
PACKAGE_PATH="${PACKAGE_PATH:-"$DEPLOY_DIR/iot_app_package.tar.gz"}"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Deployment environment file was not found:"
  echo "  $ENV_FILE"
  echo "Run ./02_create_iot_ec2.sh first."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

SSH_USER="${SSH_USER:-ubuntu}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/opt/smart-city-iot}"
APP_PORT="${APP_PORT:-5177}"
KEY_FILE="${KEY_FILE:-"$HOME/.ssh/${KEY_NAME}.pem"}"

echo "Refreshing the current EC2 public IP from AWS."
echo "This matters because a public IP can change after an instance is stopped and started."
REFRESHED_PUBLIC_IP="$(aws ec2 describe-instances \
  --region "${REGION:-$AWS_DEFAULT_REGION}" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text 2>/dev/null || true)"

if [ -n "$REFRESHED_PUBLIC_IP" ] && [ "$REFRESHED_PUBLIC_IP" != "None" ]; then
  PUBLIC_IP="$REFRESHED_PUBLIC_IP"
else
  echo "ERROR: Could not find a current public IP for instance $INSTANCE_ID."
  echo "Check that the instance is running and has a public IPv4 address."
  exit 1
fi

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 4: Upload and install app"
echo "============================================================"
echo "Public IP      : $PUBLIC_IP"
echo "SSH user       : $SSH_USER"
echo "Key file       : $KEY_FILE"
echo "Package        : $PACKAGE_PATH"
echo "Remote app dir : $REMOTE_APP_DIR"
echo "Internal port  : $APP_PORT"
echo

if [ ! -f "$PACKAGE_PATH" ]; then
  echo "ERROR: Package file was not found."
  echo "Run ./03_package_iot_app.sh first."
  exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "ERROR: SSH private key file was not found:"
  echo "  $KEY_FILE"
  echo
  echo "Set KEY_FILE to the local path of your .pem file."
  echo "Example:"
  echo "  KEY_FILE=\"/mnt/e/trycli/verified_cli/deployment/week11-verified-sunlit.pem\" ./04_upload_and_install_iot_app.sh"
  exit 1
fi

chmod 400 "$KEY_FILE" || true

echo "Waiting for SSH to become ready..."
SSH_READY=0
for attempt in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -i "$KEY_FILE" "$SSH_USER@$PUBLIC_IP" "echo ssh-ready" >/dev/null 2>&1; then
    SSH_READY=1
    break
  fi
  echo "SSH is not ready yet. Retry $attempt/30..."
  sleep 10
done
if [ "$SSH_READY" -ne 1 ]; then
  echo "ERROR: SSH did not become ready after 5 minutes."
  echo "Check KEY_FILE, KEY_NAME, public IP and security group port 22."
  exit 1
fi

echo "Uploading package to EC2 with scp..."
scp -o StrictHostKeyChecking=accept-new -i "$KEY_FILE" "$PACKAGE_PATH" "$SSH_USER@$PUBLIC_IP:/tmp/iot_app_package.tar.gz"
echo

echo "Connecting to EC2 and installing the application..."
ssh -o StrictHostKeyChecking=accept-new -i "$KEY_FILE" "$SSH_USER@$PUBLIC_IP" \
  "REMOTE_APP_DIR='$REMOTE_APP_DIR' APP_PORT='$APP_PORT' bash -s" <<'REMOTE_SCRIPT'
set -Eeuo pipefail

echo "------------------------------------------------------------"
echo "Remote install: starting on EC2"
echo "------------------------------------------------------------"
echo "Remote app directory: $REMOTE_APP_DIR"
echo "Internal app port   : $APP_PORT"
echo

case "$REMOTE_APP_DIR" in
  /opt/*)
    echo "Application directory safety check passed."
    ;;
  *)
    echo "ERROR: REMOTE_APP_DIR must be under /opt/ for this teaching script."
    echo "Current value: $REMOTE_APP_DIR"
    exit 1
    ;;
esac
echo

echo "Updating Ubuntu package index..."
sudo apt-get update

export DEBIAN_FRONTEND=noninteractive

echo "Installing base packages: curl, nginx and sqlite3..."
sudo apt-get install -y ca-certificates curl gnupg tar gzip nginx sqlite3

NODE_MAJOR="$(node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 24 ]; then
  echo "Installing Node.js 24 from NodeSource."
  echo "This app uses Node's built-in node:sqlite module, so Node.js 24+ is required."
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  echo "Node.js major version is already $NODE_MAJOR."
fi

echo "Node version:"
node --version
echo

echo "Preparing application directory..."
sudo mkdir -p "$REMOTE_APP_DIR"
sudo find "$REMOTE_APP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sudo tar -xzf /tmp/iot_app_package.tar.gz -C "$REMOTE_APP_DIR"
sudo chown -R ubuntu:ubuntu "$REMOTE_APP_DIR"

echo "Checking application files..."
test -f "$REMOTE_APP_DIR/server/server.mjs"
test -f "$REMOTE_APP_DIR/public/index.html"
test -f "$REMOTE_APP_DIR/data/smart_city_iot.sqlite"

echo "SQLite tables:"
sqlite3 "$REMOTE_APP_DIR/data/smart_city_iot.sqlite" ".tables"
echo

echo "Creating systemd service for the Node.js backend..."
sudo tee /etc/systemd/system/smart-city-iot.service >/dev/null <<SERVICE
[Unit]
Description=Smart City IoT Network Monitor
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$REMOTE_APP_DIR
Environment=PORT=$APP_PORT
Environment=IOT_DB=$REMOTE_APP_DIR/data/smart_city_iot.sqlite
ExecStart=/usr/bin/node --no-warnings $REMOTE_APP_DIR/server/server.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

echo "Starting systemd service..."
sudo systemctl daemon-reload
sudo systemctl enable smart-city-iot
sudo systemctl restart smart-city-iot
sleep 3
sudo systemctl --no-pager --full status smart-city-iot || true
echo

echo "Configuring Nginx reverse proxy."
echo "Public users will visit port 80. Nginx will forward traffic to Node on localhost:$APP_PORT."
sudo tee /etc/nginx/sites-available/smart-city-iot >/dev/null <<NGINX
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Server-Sent Events need buffering disabled so stream updates are not delayed.
        proxy_buffering off;
        proxy_cache off;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/smart-city-iot /etc/nginx/sites-enabled/smart-city-iot
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

echo "Testing local backend through Node..."
curl -fsS "http://127.0.0.1:$APP_PORT/api/health"
echo
echo

echo "Testing local public entry through Nginx..."
curl -fsS "http://127.0.0.1/api/health"
echo
echo

echo "Remote install complete."
REMOTE_SCRIPT

echo
echo "Deployment complete."
echo "Open this URL in a browser:"
echo "  http://$PUBLIC_IP/"
echo
echo "Next step:"
echo "  ./05_verify_iot_site.sh"
