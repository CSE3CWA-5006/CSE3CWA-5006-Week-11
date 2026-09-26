#!/usr/bin/env bash
# Copyright (C) 2026 Shuo Ding
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
ENV_FILE="$DEPLOY_DIR/aws_iot_instance.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: Deployment state not found: $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
ACTION="${1:-terminate}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

case "$ACTION" in
  stop)
    echo "Stopping $INSTANCE_ID. This preserves the instance and EBS volume."
    aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --output table
    ;;
  terminate)
    echo "This will terminate the lab EC2 instance and remove lab-owned deployment resources."
    echo "Type TERMINATE to confirm:"
    read -r CONFIRM
    [ "$CONFIRM" = "TERMINATE" ] || { echo "Cleanup cancelled."; exit 0; }

    STATE="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true)"
    if [ -n "$STATE" ] && [ "$STATE" != "None" ] && [ "$STATE" != "terminated" ]; then
      aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
      echo "Waiting for instance termination..."
      aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"
    fi

    if [ "${SG_CREATED_BY_LAB:-false}" = "true" ] && [ -n "${SG_ID:-}" ]; then
      echo "Deleting lab-created security group $SG_ID..."
      aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID"
    else
      if [ "${HTTP_RULE_CREATED_BY_LAB:-false}" = "true" ] && [ -n "${SG_ID:-}" ]; then
        echo "Revoking the HTTP rule added by this lab from reused security group $SG_ID..."
        aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
          --protocol tcp --port 80 --cidr "${HTTP_CIDR:-0.0.0.0/0}"
      fi
      echo "Reused security group is retained."
    fi

    rm -f "$DEPLOY_DIR/user-data.sh" "$ENV_FILE"
    echo "Cleanup complete. No SSH key pair or PEM file exists in this CloudShell-only workflow."
    ;;
  *) echo "ERROR: Use 'stop' or 'terminate'."; exit 1 ;;
esac
