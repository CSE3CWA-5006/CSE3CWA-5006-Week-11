#!/usr/bin/env bash
# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 6: Stop or terminate the EC2 instance.
#
# Usage:
#   ./06_cleanup_iot_ec2.sh stop
#   ./06_cleanup_iot_ec2.sh terminate
#
# Stop keeps the instance configuration but pauses compute.
# Terminate deletes the instance. Use terminate only when you are sure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
ENV_FILE="$DEPLOY_DIR/aws_iot_instance.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Deployment environment file was not found:"
  echo "  $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

ACTION="${1:-stop}"
if [ -n "${AWS_PROFILE:-}" ]; then
  export AWS_PROFILE
fi
export AWS_DEFAULT_REGION="${REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 6: Cleanup"
echo "============================================================"
echo "Instance ID: $INSTANCE_ID"
echo "Action     : $ACTION"
echo

# The instance may already be gone, for example when the lab was cleaned up
# twice or the instance was terminated from the AWS Console. Check the state
# first so the script reports that clearly instead of failing with a raw
# quoteless JMESPath error such as "list index out of range".
INSTANCE_STATE="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || true)"

if [ -z "$INSTANCE_STATE" ] || [ "$INSTANCE_STATE" = "None" ]; then
  echo "Instance $INSTANCE_ID was not found in ${AWS_DEFAULT_REGION}."
  echo "It may already be terminated. Nothing to clean up."
  exit 0
fi

# Select the Name tag as a single value. Asking for the whole Tags list makes
# the table formatter fail with "aws: [ERROR]: list index out of range".
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,Tags[?Key=='Name'].Value|[0]]" \
  --output table
echo

case "$ACTION" in
  stop)
    echo "Stopping instance. This pauses compute charges but keeps the instance record and disk."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --output table
    ;;
  terminate)
    echo "WARNING: Terminating deletes the EC2 instance."
    echo "Type TERMINATE to confirm:"
    read -r CONFIRM
    if [ "$CONFIRM" != "TERMINATE" ]; then
      echo "Termination cancelled."
      exit 0
    fi
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --output table
    ;;
  *)
    echo "ERROR: Unknown action: $ACTION"
    echo "Use: stop or terminate"
    exit 1
    ;;
esac

echo
echo "Cleanup command sent."
echo "Check the AWS Console or run ./01_cli_login_check.sh to confirm the new state."
