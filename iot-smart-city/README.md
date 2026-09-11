# Smart City IoT Network Monitor

Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

License: GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See [`LICENSE`](LICENSE) for the full license text.

## What this project is

This is the Week 11 Smart City IoT teaching project for CSE3CWA/CSE5CWA. It is a React + Node.js + SQLite web application that students deploy to the Internet on an Ubuntu-based AWS EC2 instance by using AWS CLI.

The main student task is cloud deployment:

1. Sign in to the AWS Console with GitHub.
2. Open AWS CloudShell from the AWS Console.
3. `git clone` this repository in CloudShell.
4. Run the Page 4 / Lab 3 Bash scripts.
5. Create one temporary Ubuntu EC2 instance.
6. Upload and run the IoT website on that EC2 instance.
7. Open the public Internet URL.
8. Terminate the EC2 instance after testing.

The current verified AWS workflow uses:

- AWS new experience project: `Sunlit Servers`
- AWS CLI environment: AWS CloudShell using the current Console session
- Selected AWS Region: `ap-southeast-2`
- EC2 instance type: `t3.micro`
- Runtime: Ubuntu 24.04, Node.js 24, SQLite, Nginx
- Public lab URL pattern: `http://EC2_PUBLIC_IP/`

This lab intentionally uses plain HTTP on port 80 to keep the beginner CLI deployment simple and low-cost. It is not a production HTTPS pattern. A production deployment should use HTTPS with a domain name and TLS certificate, for example through CloudFront and AWS Certificate Manager.

## Student cloud deployment quick start

This is the primary Week 11 lab path. Students do all commands online in AWS CloudShell. CloudShell is opened from the AWS Console after the GitHub sign-in session is already active.

The CloudShell terminal is where you type the commands. The website itself is deployed to a separate Ubuntu EC2 instance on AWS and opened through a public Internet URL.

Quick environment check:

```bash
bash --version
aws --version
git --version
ssh -V
scp -V || true
```

### 1. Open AWS CloudShell and check CLI access

```bash
aws --version
aws configure set region ap-southeast-2
aws sts get-caller-identity
aws freetier get-account-plan-state --region ap-southeast-2
```

CloudShell uses the current AWS Console session.

### 2. Clone the repository

```bash
git clone https://github.com/CSE3CWA-5006/CSE3CWA-5006-Week-11.git
cd CSE3CWA-5006-Week-11/iot-smart-city/scripts
chmod +x *.sh
```

### 3. Run the cloud deployment scripts

Step 1: check AWS CLI login:

```bash
./01_cli_login_check.sh
```

Step 2: create one Ubuntu EC2 instance:

```bash
OWNER="student-12345678" ./02_create_iot_ec2.sh
```

Step 3: package the cloned IoT app:

```bash
./03_package_iot_app.sh
```

Step 4: upload and install the app on EC2:

```bash
./04_upload_and_install_iot_app.sh
```

Step 5: verify the public Internet website:

```bash
./05_verify_iot_site.sh
```

The verification script prints the public URL:

```text
http://EC2_PUBLIC_IP/
```

Open that URL in a browser. This is the deployed Internet website.

Step 6: terminate the temporary EC2 instance:

```bash
./06_cleanup_iot_ec2.sh terminate
```

Only stop instead of terminate if your lecturer explicitly asks you to keep the instance:

```bash
./06_cleanup_iot_ec2.sh stop
```
```

### 4. Open and inspect the Ubuntu EC2 configuration

After `02_create_iot_ec2.sh` finishes, you can inspect the instance in the AWS Management Console:

```text
AWS Management Console > EC2 > Instances
```

Use the selected Region:

```text
ap-southeast-2
```

Find the instance with the Week 11 tags printed by the script. Check these fields:

- Instance state: `Running`
- Public IPv4 address: this becomes the website address
- Instance type: `t3.micro`
- Platform/runtime: Ubuntu Linux
- Security group inbound rules:
  - TCP `22` from your current public IP only, for SSH and `scp`
  - TCP `80` from `0.0.0.0/0`, for the public teaching website

The public website URL is:

```text
http://EC2_PUBLIC_IP/
```

This lab uses HTTP, not HTTPS, because no domain name or certificate is configured. For production HTTPS you need a domain name plus TLS, for example Amazon CloudFront or an HTTPS load balancer with an AWS Certificate Manager certificate.

## Important cost warning

The AWS deployment creates a real EC2 instance. Even a small teaching instance can consume free-tier credits or create charges if it is left running.

After testing the website, you must terminate the temporary EC2 instance unless your lecturer explicitly tells you to keep it.

For the Bash lab scripts, cleanup is:

```bash
./06_cleanup_iot_ec2.sh terminate
```

## Data notice

All scenario information, map placement, sensor identifiers, place names, areas, coordinates, readings, and related display data used by this project are fake, synthetic, anonymized, or relocated for testing only.

These data are not real operational, municipal, infrastructure, or sensor records. They are provided only to test the software and support teaching.

The included SQLite database is intentionally kept in this repository so students can clone the project and run the lab without rebuilding the database first:

```text
data/smart_city_iot.sqlite
```

Runtime files are intentionally not kept in Git:

```text
data/*.pid
data/*.url
scripts/__pycache__/
node_modules/
*.log
```

## Repository structure

```text
iot-smart-city/
├── data/
│   ├── smart_city_iot.sqlite       # teaching database, intentionally retained
│   └── dele.py                     # helper/legacy data utility
├── public/
│   ├── index.html
│   └── src/
│       ├── app.js                  # React UI
│       └── styles.css
├── scripts/
│   ├── 01_cli_login_check.sh
│   ├── 02_create_iot_ec2.sh
│   ├── 03_package_iot_app.sh
│   ├── 04_upload_and_install_iot_app.sh
│   ├── 05_verify_iot_site.sh
│   └── 06_cleanup_iot_ec2.sh
├── server/
│   └── server.mjs                  # Node.js server and API
├── package.json
├── LICENSE
└── README.md
```

## How the scripts relate to the teaching pages

The `scripts/` folder is the executable code for the Page 4 and Lab 3 deployment lab.

- Page 1 explains AWS resources and why Region, tags, security groups and EC2 matter.
- Page 2 explains AWS CLI command grammar and the EC2 workflow.
- Page 3 explains architecture and automation thinking.
- Page 4 explains the Smart City IoT deployment workflow and the scripts.
- Lab 3 gives the step-by-step student commands.

In short:

```text
Page 1-3 = concepts and CLI foundations
Page 4   = deployment explanation
Lab 3    = student step-by-step lab
scripts/ = real executable CLI code used by Page 4 and Lab 3
```

There is no hidden second set of student deployment scripts. The student copy in this repository is:

```text
iot-smart-city/scripts
```

Scripts `01` through `06` are aligned with the verified CLI workflow.

## Page 4 / Lab 3 script details

The following section explains what each student cloud deployment script does. It is the same workflow used by Page 4 and Lab 3.

### `01_cli_login_check.sh`

This read-only script confirms:

- AWS CLI is installed
- profile `sunlit` is signed in
- selected Region is `ap-southeast-2`
- the CLI can call AWS STS
- existing Week 11 EC2 instances can be listed

### `02_create_iot_ec2.sh`

This is the first script that creates cloud resources. It:

- checks AWS identity
- checks `t3.micro` is Free Tier eligible in the selected Region
- creates the EC2 key pair if it does not already exist
- by default, names the key pair from `OWNER`, for example `week11-iot-student-12345678`
- saves a new private key file under `../deployment/`, for example `../deployment/week11-iot-student-12345678.pem`
- finds the default VPC and subnet
- creates or reuses a security group
- opens SSH port 22 from your current IP
- opens HTTP port 80 for browser access
- launches one Ubuntu EC2 instance
- waits until the instance is running
- saves the instance id and public IP to `../deployment/aws_iot_instance.env`

### `03_package_iot_app.sh`

This packages the cloned website and included SQLite database into:

```text
../deployment/iot_app_package.tar.gz
```

It does not create or change AWS resources.

### `04_upload_and_install_iot_app.sh`

This installs the website on the EC2 instance. It:

- refreshes the current public IP from AWS
- waits for SSH
- uploads the app package with `scp`
- installs Node.js 24, SQLite and Nginx on EC2
- extracts the app to `/opt/smart-city-iot`
- creates `smart-city-iot.service`
- configures Nginx as the public HTTP reverse proxy
- checks the Node backend and public Nginx entry point

### `05_verify_iot_site.sh`

This verifies the public Internet deployment:

```text
http://EC2_PUBLIC_IP/
http://EC2_PUBLIC_IP/api/health
http://EC2_PUBLIC_IP/api/bootstrap
http://EC2_PUBLIC_IP/api/stream
```

### `06_cleanup_iot_ec2.sh`

This stops or terminates the temporary EC2 instance. For this credit-limited lab, the required end-of-lab action is:

```bash
./06_cleanup_iot_ec2.sh terminate
```

## Detailed AWS CLI deployment notes

Use this when the lab asks you to deploy the IoT website to AWS.

The deployment creates one temporary Ubuntu EC2 instance, uploads this app, runs it with Node.js 24, and exposes it through Nginx on public HTTP port 80.

### Before you start

Confirm the selected Region in AWS Settings:

```text
AWS Settings > View all projects > Overview > Additional info > Region
```

For the verified Week 11 project, the selected Region is:

```text
ap-southeast-2
```

Open AWS CloudShell from the AWS Console and confirm CLI access:

```bash
aws --version
aws configure set region ap-southeast-2
aws sts get-caller-identity
aws freetier get-account-plan-state --region ap-southeast-2
```

CloudShell uses the current Console session for the student lab.

### Bash step-by-step path

Use this path in AWS CloudShell when following Page 4 / Lab 3 step by step.

Clone the repository and enter the scripts folder:

```bash
git clone https://github.com/CSE3CWA-5006/CSE3CWA-5006-Week-11.git
cd CSE3CWA-5006-Week-11/iot-smart-city/scripts
chmod +x *.sh
```

Step 1: check AWS CLI login:

```bash
./01_cli_login_check.sh
```

Step 2: create one EC2 instance:

```bash
OWNER="student-12345678" ./02_create_iot_ec2.sh
```

This script:

- checks AWS identity
- checks `t3.micro` is Free Tier eligible in the selected Region
- creates or reuses the EC2 key pair
- by default, names the key pair from `OWNER`, for example `week11-iot-student-12345678`
- saves a new private key file under `../deployment/`, for example `../deployment/week11-iot-student-12345678.pem`
- finds the default VPC and subnet
- creates or reuses a security group
- opens SSH port 22 from your current IP
- opens HTTP port 80 for browser access
- launches one Ubuntu EC2 instance
- waits until the instance is running
- saves the instance id and public IP to `../deployment/aws_iot_instance.env`

Step 3: package the app:

```bash
./03_package_iot_app.sh
```

The default source directory is the cloned `iot-smart-city` folder. You normally do not need `IOT_SOURCE_DIR`.

Only if your lecturer asks you to package a different copy, set `IOT_SOURCE_DIR` explicitly:

```bash
IOT_SOURCE_DIR="/path/to/iot-smart-city" ./03_package_iot_app.sh
```

Step 4: upload and install the app:

```bash
./04_upload_and_install_iot_app.sh
```

This script:

- refreshes the current public IP from AWS
- waits for SSH
- uploads the app package with `scp`
- installs Node.js 24, SQLite and Nginx on EC2
- extracts the app to `/opt/smart-city-iot`
- creates `smart-city-iot.service`
- configures Nginx as the public HTTP reverse proxy
- checks both the EC2-internal backend and public Nginx entry point

Step 5: verify the public website:

```bash
./05_verify_iot_site.sh
```

Expected checks:

```text
http://EC2_PUBLIC_IP/
http://EC2_PUBLIC_IP/api/health
http://EC2_PUBLIC_IP/api/bootstrap
http://EC2_PUBLIC_IP/api/stream
```

Step 6: terminate the EC2 instance after the lab:

```bash
./06_cleanup_iot_ec2.sh terminate
```

Only stop instead of terminate if your lecturer explicitly asks you to keep the instance:

```bash
./06_cleanup_iot_ec2.sh stop
```

## What success looks like

A successful deployment shows:

- the browser opens the Smart City IoT dashboard
- `/api/health` returns JSON with `"ok": true`
- `/api/bootstrap` returns sensor metadata
- `/api/stream` returns Server-Sent Events such as `event: init` and `event: tick`
- the EC2 service `smart-city-iot` is active
- Nginx is active

The verified deployment tested these results against a fresh clone of the GitHub repository.

## Why the website may load slowly the first time

The backend API is small and should respond quickly. If the page appears slow on first load, the most likely reason is that the frontend uses public CDN resources:

```html
https://unpkg.com/leaflet@1.9.4/dist/leaflet.css
https://unpkg.com/leaflet@1.9.4/dist/leaflet.js
https://esm.sh/react@18.3.1
https://esm.sh/react-dom@18.3.1/client
https://esm.sh/lucide-react@0.468.0?external=react
```

School networks, browser cache misses, or cross-region CDN latency can make the first browser load slower. After the browser caches these files, reloads are usually faster.

For a production or fully offline teaching package, bundle these dependencies locally instead of loading them from CDNs.

## Troubleshooting

### `aws sts get-caller-identity` fails

In CloudShell, first confirm that the current Console session is still active:

```bash
aws sts get-caller-identity
```

Then retry the lab script:

```bash
./01_cli_login_check.sh
```

### `t3.micro is not Free Tier eligible`

Do not continue blindly. Check the Free Tier eligible instance types for the selected Region:

```bash
aws ec2 describe-instance-types \
  --region ap-southeast-2 \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[*].InstanceType' \
  --output table
```

Use only an instance type allowed by the current project and lab instructions.

### SSH fails

Check:

- the EC2 instance is running
- `KEY_NAME` is the AWS key pair name
- `KEY_FILE` is the matching private `.pem` file
- port 22 is open to your current public IP
- the username is `ubuntu` for the Ubuntu AMI used by this lab

### Browser cannot open the website

Check:

- the public URL uses `http://`, not `https://`
- port 80 is open in the security group
- Nginx is active
- the Node service is active
- the EC2 public IP has not changed after stop/start

### The old public URL stopped working

Normal EC2 public IPv4 addresses can change after stop/start. Query the current IP again:

```bash
source ../deployment/aws_iot_instance.env
aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text
```

### Cleanup is unclear

When in doubt, terminate the temporary lab instance after evidence has been collected:

```bash
./06_cleanup_iot_ec2.sh terminate
```

This protects the project from unnecessary credit usage and possible charges.

## Final publication checklist

Before publishing or teaching this lab, confirm:

- `data/smart_city_iot.sqlite` exists
- no `data/*.pid` or `data/*.url` files are committed
- no `scripts/__pycache__/` files are committed
- `scripts/01_cli_login_check.sh` uses profile `sunlit`, not an access-key paste workflow
- `scripts/02_create_iot_ec2.sh` uses `t3.micro` and checks Free Tier eligibility
- all regional AWS resources are created in `ap-southeast-2`
- the lab ending tells students to terminate the temporary EC2 instance
