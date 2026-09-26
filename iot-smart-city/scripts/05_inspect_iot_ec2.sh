#!/usr/bin/env bash
# Copyright (C) 2026 Shuo Ding
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/deployment/aws_iot_instance.env"
[ -f "$ENV_FILE" ] || { echo "ERROR: Deployment state not found."; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

echo "EC2 resource state:"
aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,AZ:Placement.AvailabilityZone,PublicIp:PublicIpAddress,Subnet:SubnetId,Vpc:VpcId,SecurityGroups:SecurityGroups[].GroupId,Name:Tags[?Key=='Name'].Value|[0]}" \
  --output table

echo
echo "Security group HTTP rule:"
aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[].CidrIp]' --output table

echo
echo "Public application status:"
curl -fsS "http://$PUBLIC_IP/deployment-status.txt"; echo
curl -fsS "http://$PUBLIC_IP/api/health"; echo
