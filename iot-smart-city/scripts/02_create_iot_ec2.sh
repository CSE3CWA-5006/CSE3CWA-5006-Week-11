#!/usr/bin/env bash
# Copyright (C) 2026 Shuo Ding
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail

# Creates one public teaching EC2 instance. The application is installed by
# EC2 user data (cloud-init); students do not SSH or SCP to the instance.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$PAGE_DIR/deployment"
mkdir -p "$DEPLOY_DIR"

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"
PROJECT="${PROJECT:-week11-smart-city-iot}"
OWNER="${OWNER:-student-id}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
REPO_URL="${REPO_URL:-https://github.com/CSE3CWA-5006/CSE3CWA-5006-Week-11.git}"
REPO_REF="${REPO_REF:-main}"
HTTP_CIDR="${HTTP_CIDR:-0.0.0.0/0}"

# Give each student's teaching security group a distinct, AWS-safe name.
# OWNER remains unchanged for tags; OWNER_SAFE is used only in the resource name.
OWNER_SAFE="$(printf '%s' "$OWNER" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
[ -n "$OWNER_SAFE" ] || { echo "ERROR: OWNER does not contain any characters suitable for an AWS resource name."; exit 1; }
SG_NAME="${PROJECT}-${OWNER_SAFE}-sg"

if [ "$OWNER" = "student-id" ]; then
  echo "ERROR: Set OWNER to your student identifier, for example:"
  echo '  OWNER="student-12345678" ./02_create_iot_ec2.sh'
  exit 1
fi

aws sts get-caller-identity >/dev/null

echo "Finding the default VPC..."
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
[ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] || { echo "ERROR: No default VPC in $REGION."; exit 1; }

# Prefer a subnet whose public IPv4 auto-assignment attribute is enabled.
echo "Selecting a public-capable subnet..."
SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=map-public-ip-on-launch,Values=true \
  --query 'sort_by(Subnets,&AvailabilityZone)[0].SubnetId' --output text)"
[ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "None" ] || { echo "ERROR: No subnet with MapPublicIpOnLaunch=true was found."; exit 1; }

# Verify the selected subnet has an IPv4 default route to an Internet Gateway.
ROUTE_OK="$(aws ec2 describe-route-tables --region "$REGION" \
  --filters Name=association.subnet-id,Values="$SUBNET_ID" \
  --query "length(RouteTables[].Routes[?DestinationCidrBlock=='0.0.0.0/0' && starts_with(GatewayId, 'igw-') && State=='active'])" --output text)"
if [ "$ROUTE_OK" = "0" ]; then
  ROUTE_OK="$(aws ec2 describe-route-tables --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=association.main,Values=true \
    --query "length(RouteTables[].Routes[?DestinationCidrBlock=='0.0.0.0/0' && starts_with(GatewayId, 'igw-') && State=='active'])" --output text)"
fi
[ "$ROUTE_OK" != "0" ] || { echo "ERROR: Selected subnet has no active 0.0.0.0/0 route to an Internet Gateway."; exit 1; }

echo "Creating or reusing security group..."
SG_ID="$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)"
SG_CREATED_BY_LAB=false
if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID="$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
    --description "Week 11 Smart City IoT teaching HTTP access" --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=week11},{Key=Owner,Value=${OWNER}},{Key=AutoCleanup,Value=true}]" \
    --query GroupId --output text)"
  SG_CREATED_BY_LAB=true
fi

# Add HTTP only when the exact rule is absent. Unexpected AWS errors remain visible.
HTTP_RULE_COUNT="$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`80\` && ToPort==\`80\`].IpRanges[].CidrIp | [?@=='${HTTP_CIDR}'])" --output text)"
HTTP_RULE_CREATED_BY_LAB=false
if [ "$HTTP_RULE_COUNT" = "0" ]; then
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr "$HTTP_CIDR" >/dev/null
  HTTP_RULE_CREATED_BY_LAB=true
fi

# Bootstrap requires outbound web access for Ubuntu packages, NodeSource and GitHub.
# A newly created security group normally has allow-all egress. If an existing
# per-student group is reused, verify that it still permits IPv4 HTTP and HTTPS
# (or all IPv4 protocols) rather than silently widening somebody else's rules.
echo "Checking security-group outbound access required by cloud-init..."
EGRESS_ALL_COUNT="$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query "length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol=='-1'].IpRanges[].CidrIp | [?@=='0.0.0.0/0'])" --output text)"
EGRESS_HTTP_COUNT="$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query "length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol=='tcp' && FromPort<=\`80\` && ToPort>=\`80\`].IpRanges[].CidrIp | [?@=='0.0.0.0/0'])" --output text)"
EGRESS_HTTPS_COUNT="$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
  --query "length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol=='tcp' && FromPort<=\`443\` && ToPort>=\`443\`].IpRanges[].CidrIp | [?@=='0.0.0.0/0'])" --output text)"
if [ "$EGRESS_ALL_COUNT" = "0" ] && { [ "$EGRESS_HTTP_COUNT" = "0" ] || [ "$EGRESS_HTTPS_COUNT" = "0" ]; }; then
  cat >&2 <<'MSG'
ERROR: The selected security group does not provide the outbound IPv4 web access
required by EC2 bootstrap. The instance must be able to reach Ubuntu package
repositories, NodeSource and GitHub over HTTP/HTTPS. This script will not widen
the egress rules of an existing security group automatically. Use a clean lab
security group or restore appropriate outbound access, then run the script again.
MSG
  exit 1
fi

# Resolve Ubuntu dynamically rather than hard-coding a Region-specific AMI ID.
echo "Resolving Ubuntu Server 24.04 LTS AMI..."
AMI_ID="$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text 2>/dev/null || true)"
if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
  AMI_ID="$(aws ec2 describe-images --region "$REGION" --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' Name=state,Values=available \
    --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text)"
fi
[ -n "$AMI_ID" ] && [ "$AMI_ID" != "None" ] || { echo "ERROR: Ubuntu 24.04 AMI could not be resolved."; exit 1; }

USER_DATA="$DEPLOY_DIR/user-data.sh"
cat > "$USER_DATA" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec > >(tee -a /var/log/week11-iot-bootstrap.log | logger -t week11-iot -s 2>/dev/console) 2>&1
export DEBIAN_FRONTEND=noninteractive
APP_DIR=/opt/smart-city-iot
APP_PORT=5177
REPO_URL='$REPO_URL'
REPO_REF='$REPO_REF'

status_dir=/var/www/html
mkdir -p "\$status_dir"
echo 'BOOTSTRAPPING' > "\$status_dir/deployment-status.txt"
trap 'echo FAILED > "\$status_dir/deployment-status.txt"' ERR

apt-get update
apt-get install -y ca-certificates curl gnupg git nginx sqlite3

NODE_MAJOR="\$(node -p \"Number(process.versions.node.split('.')[0])\" 2>/dev/null || echo 0)"
if [ "\$NODE_MAJOR" -lt 24 ]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi

rm -rf "\$APP_DIR"
git clone --depth 1 --branch "\$REPO_REF" "\$REPO_URL" /tmp/week11-repo
mkdir -p "\$APP_DIR"
cp -a /tmp/week11-repo/iot-smart-city/. "\$APP_DIR/"
chown -R ubuntu:ubuntu "\$APP_DIR"
test -f "\$APP_DIR/server/server.mjs"
test -f "\$APP_DIR/public/index.html"
test -f "\$APP_DIR/data/smart_city_iot.sqlite"
sqlite3 "\$APP_DIR/data/smart_city_iot.sqlite" '.tables'

cat > /etc/systemd/system/smart-city-iot.service <<SERVICE
[Unit]
Description=Smart City IoT Network Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=\$APP_DIR
Environment=PORT=\$APP_PORT
Environment=IOT_DB=\$APP_DIR/data/smart_city_iot.sqlite
ExecStart=/usr/bin/node --no-warnings \$APP_DIR/server/server.mjs
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now smart-city-iot

cat > /etc/nginx/sites-available/smart-city-iot <<NGINX
server {
    listen 80 default_server;
    server_name _;

    location = /deployment-status.txt {
        root /var/www/html;
        default_type text/plain;
        add_header Cache-Control "no-store";
    }

    location / {
        proxy_pass http://127.0.0.1:\$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/smart-city-iot /etc/nginx/sites-enabled/smart-city-iot
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

for i in \$(seq 1 30); do
  if curl -fsS http://127.0.0.1:\$APP_PORT/api/health >/dev/null && curl -fsS http://127.0.0.1/api/health >/dev/null; then
    echo 'READY' > "\$status_dir/deployment-status.txt"
    exit 0
  fi
  sleep 2
done

echo 'FAILED' > "\$status_dir/deployment-status.txt"
exit 1
EOF

# Teaching environment controls the permitted instance type. Do not hard-code
# account-specific Free Tier claims into deployment correctness.
echo "Launching $INSTANCE_TYPE in $REGION..."
INSTANCE_ID="$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --network-interfaces "DeviceIndex=0,SubnetId=${SUBNET_ID},Groups=[${SG_ID}],AssociatePublicIpAddress=true" \
  --metadata-options 'HttpTokens=required,HttpEndpoint=enabled' \
  --user-data "file://$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}},{Key=Project,Value=week11},{Key=Owner,Value=${OWNER}},{Key=Purpose,Value=iot-lab},{Key=AutoCleanup,Value=true}]" \
  --query 'Instances[0].InstanceId' --output text)"

aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
[ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ] || { echo "ERROR: Instance has no public IPv4 address."; exit 1; }

ENV_FILE="$DEPLOY_DIR/aws_iot_instance.env"
cat > "$ENV_FILE" <<EOF
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"
export REGION="$REGION"
export PROJECT="$PROJECT"
export OWNER="$OWNER"
export INSTANCE_ID="$INSTANCE_ID"
export PUBLIC_IP="$PUBLIC_IP"
export VPC_ID="$VPC_ID"
export SUBNET_ID="$SUBNET_ID"
export SG_ID="$SG_ID"
export SG_CREATED_BY_LAB="$SG_CREATED_BY_LAB"
export HTTP_CIDR="$HTTP_CIDR"
export HTTP_RULE_CREATED_BY_LAB="$HTTP_RULE_CREATED_BY_LAB"
export REPO_URL="$REPO_URL"
export REPO_REF="$REPO_REF"
EOF

echo "Instance ID : $INSTANCE_ID"
echo "Public IP   : $PUBLIC_IP"
echo "HTTP URL    : http://$PUBLIC_IP/"
echo "No SSH key was created and port 22 was not opened."
echo "Next: ./03_wait_for_iot_app.sh"
