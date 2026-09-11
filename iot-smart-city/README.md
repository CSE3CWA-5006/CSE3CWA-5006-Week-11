# Smart City IoT Network Monitor

Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

License: GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See [`LICENSE`](LICENSE) for the full license text.

## What this project is

This is the Week 11 Smart City IoT teaching project for CSE3CWA/CSE5CWA. It is a local React + Node.js + SQLite web application that replays anonymized/synthetic IoT sensor readings on a fake city map.

The repository is designed for two related uses:

1. Run the IoT website locally on Windows or Ubuntu.
2. Deploy the same website to one temporary AWS EC2 instance by following the Page 4 and Lab 3 CLI workflow.

The current verified AWS workflow uses:

- AWS new experience project: `Sunlit Servers`
- AWS CLI profile: `sunlit`
- Selected AWS Region: `ap-southeast-2`
- EC2 instance type: `t3.micro`
- Runtime: Ubuntu 24.04, Node.js 24, SQLite, Nginx
- Public lab URL pattern: `http://EC2_PUBLIC_IP/`

This lab intentionally uses plain HTTP on port 80 to keep the beginner CLI deployment simple and low-cost. It is not a production HTTPS pattern. A production deployment should use HTTPS with a domain name and TLS certificate, for example through CloudFront and AWS Certificate Manager.

## Important cost warning

The AWS deployment creates a real EC2 instance. Even a small teaching instance can consume free-tier credits or create charges if it is left running.

After testing the website, you must terminate the temporary EC2 instance unless your lecturer explicitly tells you to keep it.

For the Bash lab scripts, cleanup is:

```bash
./06_cleanup_iot_ec2.sh terminate
```

On the verified Windows path, cleanup is:

```powershell
powershell -ExecutionPolicy Bypass -File E:\trycli\verified_cli\scripts\90_verified_windows_cleanup.ps1
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
├── run_ubuntu.sh                   # local Ubuntu runner
├── run.ps1                         # Windows helper used by start_site.bat
├── start_site.bat                  # local Windows entry point
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

There is no hidden second set of student deployment scripts. The verified classroom copy also keeps the same Bash scripts in:

```text
E:\trycli\verified_cli\scripts
```

The student copy in this repository is:

```text
iot-smart-city/scripts
```

Scripts `01` through `06` are aligned with the verified CLI workflow.

## Quick start: run locally on Windows

Use this if you only want to open the IoT website on your own computer.

Open PowerShell or Command Prompt in the `iot-smart-city` folder and run:

```cmd
start_site.bat
```

Then open:

```text
http://localhost:5177
```

The Windows launcher uses `run.ps1` internally. Most students should run `start_site.bat`, not `run.ps1` directly.

Useful Windows options:

```cmd
start_site.bat -Port 8080
start_site.bat -Reimport
start_site.bat -Input "D:\iotdataback\IoTData\dataall" -Reimport
```

Because `data/smart_city_iot.sqlite` is already included, you normally do not need `-Reimport`.

## Quick start: run locally on Ubuntu

Use this if you are working in Ubuntu, WSL, or an Ubuntu EC2 terminal.

From the `iot-smart-city` folder:

```bash
chmod +x run_ubuntu.sh
./run_ubuntu.sh --skip-install
```

Then open:

```text
http://localhost:5177
```

If dependencies are not installed yet, run without `--skip-install`:

```bash
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

The Ubuntu runner installs or checks:

- Node.js 24, required for Node's built-in `node:sqlite`
- Python 3 and a virtual environment, only needed if you rebuild/import data
- `pandas` and `openpyxl`, only needed if you rebuild/import data
- SQLite command-line tools

Useful Ubuntu options:

```bash
./run_ubuntu.sh --port 8080
./run_ubuntu.sh --reimport --input ./dataall
IOT_DB=./data/smart_city_iot.sqlite PORT=5177 ./run_ubuntu.sh --skip-install
```

Because the teaching SQLite database is already included, beginners should start with the existing database and avoid `--reimport` unless the lecturer asks for it.

## AWS CLI deployment: Page 4 / Lab 3 workflow

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

Confirm AWS CLI login:

```bash
aws --version
aws configure set region ap-southeast-2 --profile sunlit
aws login --region ap-southeast-2 --profile sunlit
aws sts get-caller-identity --profile sunlit
aws freetier get-account-plan-state --region ap-southeast-2 --profile sunlit
```

During `aws login`, AWS opens a browser sign-in flow. If you are already signed in with GitHub, continue with that GitHub session and use **Add session** when AWS asks you to create or choose a CLI session.

### Recommended Windows verified path

On the prepared classroom Windows machine, the verified scripts are stored in:

```text
E:\trycli\verified_cli\scripts
```

Run:

```powershell
powershell -ExecutionPolicy Bypass -File E:\trycli\verified_cli\scripts\00_verified_windows_preflight.ps1
powershell -ExecutionPolicy Bypass -File E:\trycli\verified_cli\scripts\10_verified_windows_deploy_iot.ps1
```

When the deploy script finishes, it prints:

```text
Public URL: http://EC2_PUBLIC_IP/
Instance ID: i-...
```

Open the public URL in a browser and verify the dashboard loads.

When finished, terminate the temporary EC2 instance:

```powershell
powershell -ExecutionPolicy Bypass -File E:\trycli\verified_cli\scripts\90_verified_windows_cleanup.ps1
```

### Bash step-by-step path

Use this path in Ubuntu or WSL when following Page 4 / Lab 3 step by step.

From the scripts folder:

```bash
cd /mnt/e/trycli/IoT/scripts
chmod +x *.sh
```

Step 1: check AWS CLI login:

```bash
./01_cli_login_check.sh
```

Step 2: create one EC2 instance:

```bash
AWS_PROFILE=sunlit KEY_NAME="week11-verified-sunlit" OWNER="student-12345678" ./02_create_iot_ec2.sh
```

This script:

- checks AWS identity
- checks `t3.micro` is Free Tier eligible in the selected Region
- confirms the EC2 key pair exists
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

If the IoT project is not in the default expected folder, set `IOT_SOURCE_DIR`:

```bash
IOT_SOURCE_DIR="/mnt/e/trycli/IoT" ./03_package_iot_app.sh
```

Step 4: upload and install the app:

```bash
KEY_FILE="/mnt/e/trycli/verified_cli/deployment/week11-verified-sunlit.pem" ./04_upload_and_install_iot_app.sh
```

This script:

- refreshes the current public IP from AWS
- waits for SSH
- uploads the app package with `scp`
- installs Node.js 24, SQLite and Nginx on EC2
- extracts the app to `/opt/smart-city-iot`
- creates `smart-city-iot.service`
- configures Nginx as the public HTTP reverse proxy
- checks both the local backend and public Nginx entry point

Step 5: verify the public website:

```bash
KEY_FILE="/mnt/e/trycli/verified_cli/deployment/week11-verified-sunlit.pem" ./05_verify_iot_site.sh
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

Run:

```bash
aws login --region ap-southeast-2 --profile sunlit
```

Then retry:

```bash
aws sts get-caller-identity --profile sunlit
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
