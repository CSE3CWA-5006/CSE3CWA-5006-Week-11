#!/usr/bin/env bash
# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 1: Check AWS CLI login and basic account context.
#
# This script does not create, change, stop, or delete any AWS resource.
# It only checks that the AWS CLI can talk to the selected AWS project.

PROFILE="${AWS_PROFILE:-sunlit}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"

export AWS_PROFILE="$PROFILE"
export AWS_DEFAULT_REGION="$REGION"

echo "============================================================"
echo "Smart City IoT AWS Lab - Step 1: AWS CLI login check"
echo "============================================================"
echo "Profile: $AWS_PROFILE"
echo "Region : $AWS_DEFAULT_REGION"
echo

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: AWS CLI was not found on this computer."
  echo
  echo "Install AWS CLI v2 first, then run this script again."
  echo "Official guide: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

echo "AWS CLI version:"
aws --version
echo

echo "Assumption: the user has already logged in with AWS CLI."
echo "For this verified lab package, the expected profile is: $PROFILE"
echo "If the login has expired, renew it with:"
echo "  aws login --region $REGION --profile $PROFILE"
echo

echo "Checking who the CLI is logged in as..."
if ! aws sts get-caller-identity --output table; then
  echo
  echo "ERROR: AWS CLI identity check failed."
  echo "Common causes:"
  echo "  1. The AWS CLI profile has not been logged in."
  echo "  2. The browser sign-in session was not completed."
  echo "  3. The temporary CLI credentials have expired."
  exit 1
fi
echo

echo "Checking the configured Region..."
CONFIGURED_REGION="$(aws configure get region --profile "$PROFILE" || true)"
echo "Configured Region for profile '$PROFILE': ${CONFIGURED_REGION:-not set}"
echo "Region used by this script: $AWS_DEFAULT_REGION"
echo

echo "Listing current EC2 instances in this Region."
echo "This is still read-only. It helps you see whether any lab servers already exist."
aws ec2 describe-instances \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress,Tags[?Key=='Name'].Value|[0]]" \
  --output table || true

echo
echo "Step 1 complete."
echo "If the identity table looked correct, continue with:"
echo "  AWS_PROFILE=\"sunlit\" OWNER=\"student-12345678\" ./02_create_iot_ec2.sh"
