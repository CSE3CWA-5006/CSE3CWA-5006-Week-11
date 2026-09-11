#!/usr/bin/env bash
# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 2: Create one Ubuntu EC2 instance for the Smart City IoT app.
#
# This script creates:
#   - one security group, or reuses it if it already exists
#   - one Ubuntu 24.04 EC2 instance
#   - tags for ownership and cleanup
#
# It stores the instance details in:
#   ../deployment/aws_iot_instance.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
mkdir -p "$DEPLOY_DIR"

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
PROJECT="${PROJECT:-week11-smart-city-iot}"
OWNER="${OWNER:-student-id}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
SAFE_OWNER="${OWNER//[^A-Za-z0-9-]/-}"
KEY_NAME="${KEY_NAME:-week11-iot-${SAFE_OWNER}}"
KEY_FILE="${KEY_FILE:-"$DEPLOY_DIR/${KEY_NAME}.pem"}"
SSH_CIDR="${SSH_CIDR:-}"
HTTP_CIDR="${HTTP_CIDR:-0.0.0.0/0}"

if [ -n "$PROFILE" ]; then
  export AWS_PROFILE="$PROFILE"
fi
export AWS_DEFAULT_REGION="$REGION"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 2: Create EC2 instance"
echo "============================================================"
echo "Profile       : ${AWS_PROFILE:-current CloudShell/default CLI session}"
echo "Region        : $AWS_DEFAULT_REGION"
echo "Project       : $PROJECT"
echo "Owner         : $OWNER"
echo "Instance type : $INSTANCE_TYPE"
echo "Key pair name : $KEY_NAME"
echo "Key file      : $KEY_FILE"
echo

echo "Checking AWS identity before creating anything..."
aws sts get-caller-identity --output table
echo

echo "Checking whether the selected instance type is Free Tier eligible in this Region..."
FREE_TIER_MATCH="$(aws ec2 describe-instance-types \
  --instance-types "$INSTANCE_TYPE" \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[0].InstanceType' \
  --output text 2>/dev/null || true)"
if [ "$FREE_TIER_MATCH" != "$INSTANCE_TYPE" ]; then
  echo "ERROR: $INSTANCE_TYPE is not Free Tier eligible in $REGION for this project."
  echo "Choose one from:"
  aws ec2 describe-instance-types \
    --filters Name=free-tier-eligible,Values=true \
    --query 'InstanceTypes[*].InstanceType' \
    --output table
  exit 1
fi
echo "$INSTANCE_TYPE is Free Tier eligible."
echo

echo "Ensuring the EC2 key pair exists in this Region..."
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Reusing existing AWS key pair: $KEY_NAME"
  if [ ! -f "$KEY_FILE" ]; then
    echo "ERROR: AWS key pair '$KEY_NAME' already exists, but the matching local PEM file was not found:"
    echo "  $KEY_FILE"
    echo "Use a KEY_NAME whose PEM file you already have, or ask the lecturer before deleting/recreating the key pair."
    exit 1
  fi
else
  echo "Creating new AWS key pair: $KEY_NAME"
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --key-type rsa \
    --key-format pem \
    --query 'KeyMaterial' \
    --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo "Saved private key file:"
  echo "  $KEY_FILE"
fi
aws ec2 describe-key-pairs \
  --key-names "$KEY_NAME" \
  --query "KeyPairs[*].[KeyName,KeyType,KeyFingerprint]" \
  --output table
echo

echo "Finding the default VPC..."
VPC_ID="$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)"

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "ERROR: No default VPC was found in Region $REGION."
  echo "For this beginner lab, use a Region with a default VPC or ask the lecturer."
  exit 1
fi
echo "Default VPC: $VPC_ID"
echo

echo "Finding one subnet in the default VPC..."
SUBNET_ID="$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'Subnets[0].SubnetId' \
  --output text)"

if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
  echo "ERROR: No subnet was found in VPC $VPC_ID."
  exit 1
fi
echo "Subnet: $SUBNET_ID"
echo

if [ -z "$SSH_CIDR" ]; then
  CURRENT_IP="$(curl -fsS https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n' || true)"
  if [ -n "$CURRENT_IP" ]; then
    SSH_CIDR="${CURRENT_IP}/32"
  else
    echo "ERROR: Could not detect current public IP for SSH_CIDR."
    echo "Set SSH_CIDR manually, for example:"
    echo "  SSH_CIDR=\"203.0.113.10/32\" KEY_NAME=\"$KEY_NAME\" ./02_create_iot_ec2.sh"
    exit 1
  fi
fi
echo "SSH CIDR: $SSH_CIDR"
echo "HTTP CIDR: $HTTP_CIDR"
echo

echo "Creating or reusing a security group..."
SG_NAME="${PROJECT}-sg"
SG_ID="$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)"

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  SG_ID="$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Week 11 Smart City IoT teaching security group" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)"
  echo "Created security group: $SG_ID"
else
  echo "Reusing security group: $SG_ID"
fi
echo

echo "Adding inbound SSH and HTTP rules."
echo "SSH is needed for deployment. HTTP is needed for browser access."
echo "If a rule already exists, AWS may return a duplicate rule message; that is acceptable."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr "$SSH_CIDR" 2>/dev/null || echo "SSH rule already exists or was not changed."

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr "$HTTP_CIDR" 2>/dev/null || echo "HTTP rule already exists or was not changed."
echo

echo "Finding the latest Ubuntu Server 24.04 LTS AMI."
echo "First trying Canonical's public SSM parameter. If that fails, using EC2 image search."
AMI_ID="$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || true)"

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
  AMI_ID="$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
    --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
    --output text)"
fi

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
  echo "ERROR: Could not find an Ubuntu 24.04 AMI in $REGION."
  echo "Ask the lecturer, or change REGION to a supported AWS Region."
  exit 1
fi
echo "Ubuntu AMI: $AMI_ID"
echo

echo "Launching one EC2 instance."
echo "The instance will receive a public IPv4 address so the class can open it in a browser."
INSTANCE_ID="$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --network-interfaces "DeviceIndex=0,SubnetId=${SUBNET_ID},Groups=[${SG_ID}],AssociatePublicIpAddress=true" \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}},{Key=Project,Value=week11},{Key=Owner,Value=${OWNER}},{Key=Purpose,Value=iot-lab},{Key=AutoCleanup,Value=true}]" \
  --query 'Instances[0].InstanceId' \
  --output text)"

echo "Instance created: $INSTANCE_ID"
echo "Waiting until the instance is running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

echo "Fetching public IP address..."
PUBLIC_IP="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)"

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "None" ]; then
  echo "ERROR: The instance does not have a public IP address."
  echo "Check subnet public IP settings or recreate the instance."
  exit 1
fi

ENV_FILE="$DEPLOY_DIR/aws_iot_instance.env"
cat > "$ENV_FILE" <<EOF
export AWS_DEFAULT_REGION="$REGION"
export REGION="$REGION"
export PROJECT="$PROJECT"
export OWNER="$OWNER"
export INSTANCE_ID="$INSTANCE_ID"
export PUBLIC_IP="$PUBLIC_IP"
export KEY_NAME="$KEY_NAME"
export KEY_FILE="$KEY_FILE"
export SSH_USER="ubuntu"
EOF

if [ -n "$PROFILE" ]; then
  sed -i "1iexport AWS_PROFILE=\"$PROFILE\"" "$ENV_FILE"
fi

echo
echo "EC2 instance is ready."
echo "Public IP: $PUBLIC_IP"
echo "Website URL after app installation: http://$PUBLIC_IP/"
echo "Saved deployment information to:"
echo "  $ENV_FILE"
echo
echo "The upload script will wait for SSH before it installs the app."
echo
echo "Next step:"
echo "  ./03_package_iot_app.sh"
