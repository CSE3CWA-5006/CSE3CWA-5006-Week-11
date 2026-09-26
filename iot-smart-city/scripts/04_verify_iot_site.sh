#!/usr/bin/env bash
# Copyright (C) 2026 Shuo Ding
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/deployment/aws_iot_instance.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: Deployment state not found."; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
[ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ] || { echo "ERROR: No current public IPv4 address."; exit 1; }

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 4: Verify public application"
echo "============================================================"
echo "URL: http://$PUBLIC_IP/"

HEALTH_FILE="${TMPDIR:-/tmp}/week11-health.json"
BOOTSTRAP_FILE="${TMPDIR:-/tmp}/week11-bootstrap.json"
STREAM_FILE="${TMPDIR:-/tmp}/week11-stream.txt"

curl -fsS "http://$PUBLIC_IP/api/health" -o "$HEALTH_FILE"
grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' "$HEALTH_FILE" || { echo "ERROR: Health response did not report ok=true."; cat "$HEALTH_FILE"; exit 1; }
echo "Health endpoint: PASS"
cat "$HEALTH_FILE"; echo

curl -fsS "http://$PUBLIC_IP/api/bootstrap" -o "$BOOTSTRAP_FILE"
[ -s "$BOOTSTRAP_FILE" ] || { echo "ERROR: Bootstrap response is empty."; exit 1; }
echo "Bootstrap endpoint: PASS"
head -c 600 "$BOOTSTRAP_FILE"; echo; echo

# The SSE connection is intentionally stopped after a few seconds. The timeout
# status is expected; the content is then asserted separately.
: > "$STREAM_FILE"
timeout 8 curl -fsS -N "http://$PUBLIC_IP/api/stream?speed=3600&maxRows=5" -o "$STREAM_FILE" || rc=$?
rc="${rc:-0}"
if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
  echo "ERROR: SSE request failed with curl/timeout status $rc."
  exit 1
fi
grep -Eq '^event: (init|tick)' "$STREAM_FILE" || { echo "ERROR: Expected SSE events were not received."; cat "$STREAM_FILE"; exit 1; }
echo "SSE endpoint: PASS"
head -n 20 "$STREAM_FILE"

echo
echo "Verification complete. Open http://$PUBLIC_IP/ in a browser."
echo "No SSH session is required for this lab."
