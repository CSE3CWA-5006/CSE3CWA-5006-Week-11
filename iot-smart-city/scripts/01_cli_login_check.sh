#!/usr/bin/env bash
set -Eeuo pipefail

# Week 11 Page 4 Lab
# Step 1: Check AWS CLI login and basic account context.
#
# This script does not create, change, stop, or delete any AWS resource.
# It only checks that the AWS CLI can talk to the correct AWS Academy account.

PROFILE="${AWS_PROFILE:-academy}"
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

echo "If this is your first time using the AWS Academy CLI credentials,"
echo "copy your temporary credentials from the AWS Academy lab page."
echo "Then run commands like these. Do not share these values with anyone:"
echo
cat <<'COMMANDS'
aws configure set aws_access_key_id "PASTE_ACCESS_KEY_ID_HERE" --profile academy
aws configure set aws_secret_access_key "PASTE_SECRET_ACCESS_KEY_HERE" --profile academy
aws configure set aws_session_token "PASTE_SESSION_TOKEN_HERE" --profile academy
aws configure set region ap-southeast-2 --profile academy
aws configure set output json --profile academy
export AWS_PROFILE=academy
COMMANDS
echo

echo "Checking who the CLI is logged in as..."
if ! aws sts get-caller-identity --output table; then
  echo
  echo "ERROR: AWS CLI identity check failed."
  echo "Common causes:"
  echo "  1. The AWS Academy lab has not started."
  echo "  2. The temporary credentials were copied incorrectly."
  echo "  3. The session token is missing."
  echo "  4. The temporary credentials have expired."
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
echo "  KEY_NAME=\"your-ec2-key-pair-name\" OWNER=\"your-student-id\" ./02_create_iot_ec2.sh"

