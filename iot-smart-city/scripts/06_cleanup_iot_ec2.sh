#!/usr/bin/env bash
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
export AWS_PROFILE="${AWS_PROFILE:-academy}"
export AWS_DEFAULT_REGION="${REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 6: Cleanup"
echo "============================================================"
echo "Instance ID: $INSTANCE_ID"
echo "Action     : $ACTION"
echo

aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,Tags]' \
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

