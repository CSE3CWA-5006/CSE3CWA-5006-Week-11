#!/usr/bin/env bash
# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 5: Verify the deployed Smart City IoT site.
#
# This script tests:
#   - public HTTP health endpoint
#   - bootstrap API
#   - Server-Sent Events stream
#   - remote systemd status and logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
ENV_FILE="$DEPLOY_DIR/aws_iot_instance.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Deployment environment file was not found:"
  echo "  $ENV_FILE"
  echo "Run ./02_create_iot_ec2.sh first."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

SSH_USER="${SSH_USER:-ubuntu}"
KEY_FILE="${KEY_FILE:-"$HOME/.ssh/${KEY_NAME}.pem"}"

echo "Refreshing the current EC2 public IP from AWS."
echo "This avoids using an old IP if the instance has been stopped and started."
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
echo "Smart City IoT AWS Lab - Step 5: Verify deployed site"
echo "============================================================"
echo "Public IP: $PUBLIC_IP"
echo "URL      : http://$PUBLIC_IP/"
echo

echo "Testing public health endpoint:"
curl -fsS "http://$PUBLIC_IP/api/health"
echo
echo

echo "Testing public bootstrap endpoint."
echo "Only the first 800 characters are shown because the response can be large."
# Save the response first instead of piping it into head. Piping a large
# response into head closes the pipe early, which makes curl exit with
# "curl: (23) Failure writing output" and stops the script under pipefail.
BOOTSTRAP_FILE="${TMPDIR:-/tmp}/iot_bootstrap.json"
curl -fsS "http://$PUBLIC_IP/api/bootstrap" -o "$BOOTSTRAP_FILE"
head -c 800 "$BOOTSTRAP_FILE"
echo
echo

echo "Testing Server-Sent Events stream for a few seconds."
echo "If you see event: init or event: tick, the live stream route is working."
# timeout ends the stream on purpose, so that exit status is expected and is
# not treated as a deployment failure.
STREAM_FILE="${TMPDIR:-/tmp}/iot_stream.txt"
timeout 6 curl -fsS -N "http://$PUBLIC_IP/api/stream?speed=3600&maxRows=5" -o "$STREAM_FILE" || true
head -n 20 "$STREAM_FILE" || true
echo

if [ -f "$KEY_FILE" ]; then
  echo "Checking remote service status through SSH..."
  ssh -o StrictHostKeyChecking=accept-new -i "$KEY_FILE" "$SSH_USER@$PUBLIC_IP" \
    "sudo systemctl --no-pager --full status smart-city-iot || true; echo; sudo journalctl -u smart-city-iot -n 30 --no-pager"
else
  echo "SSH key file was not found, so remote systemd status was skipped:"
  echo "  $KEY_FILE"
fi

echo
echo "Verification complete."
echo "For submission evidence, capture:"
echo "  1. Browser showing http://$PUBLIC_IP/"
echo "  2. curl /api/health response"
echo "  3. systemctl status smart-city-iot output"
