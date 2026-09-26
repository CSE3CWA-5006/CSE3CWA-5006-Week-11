#!/usr/bin/env bash
# Copyright (C) 2026 Shuo Ding
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 1: CloudShell context check"
echo "============================================================"
command -v aws >/dev/null 2>&1 || { echo "ERROR: AWS CLI is not available."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: Git is not available."; exit 1; }
aws --version
git --version
echo "CloudShell AWS_REGION : ${AWS_REGION:-not set}"
echo "Region used by lab   : $REGION"
echo

echo "AWS identity:"
aws sts get-caller-identity --output table

echo "Existing EC2 instances in $REGION:"
aws ec2 describe-instances --region "$REGION" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress,Tags[?Key=='Name'].Value|[0]]" \
  --output table

echo
echo "Step 1 complete. No AWS resources were modified."
echo "Next: OWNER=\"student-12345678\" ./02_create_iot_ec2.sh"
