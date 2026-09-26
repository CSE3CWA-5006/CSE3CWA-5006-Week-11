#!/usr/bin/env bash
# Copyright (C) 2026 Shuo Ding
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/deployment/aws_iot_instance.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: Run ./02_create_iot_ec2.sh first."; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 3: Wait for cloud-init deployment"
echo "============================================================"
echo "Instance: $INSTANCE_ID"
echo "URL     : http://$PUBLIC_IP/"
echo

# EC2 'running' means the VM is powered on; it does not mean user data has
# finished installing the application. Poll the application-level status.
for attempt in $(seq 1 60); do
  status="$(curl -fsS --connect-timeout 3 --max-time 5 "http://$PUBLIC_IP/deployment-status.txt" 2>/dev/null || true)"
  case "$status" in
    READY)
      echo "Application deployment status: READY"
      curl -fsS "http://$PUBLIC_IP/api/health"
      echo
      echo "Next: ./04_verify_iot_site.sh"
      exit 0
      ;;
    FAILED)
      echo "ERROR: EC2 user-data installation reported FAILED."
      echo "Use the EC2 Console system log to inspect /var/log/week11-iot-bootstrap.log output."
      exit 1
      ;;
    *)
      printf 'Waiting for application bootstrap... %s/60\r' "$attempt"
      sleep 10
      ;;
  esac
done

echo
echo "ERROR: Application did not become ready within 10 minutes."
echo "Check EC2 > Instances > Monitor and troubleshoot > Get system log."
exit 1
