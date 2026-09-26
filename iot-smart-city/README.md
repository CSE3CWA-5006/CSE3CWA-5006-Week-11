# Smart City IoT Network Monitor — Week 11 AWS Deployment

This teaching project deploys a Smart City IoT dashboard to one Ubuntu EC2 instance using **AWS CloudShell and AWS CLI automation only**. Students do not SSH to the instance, do not use `scp`, do not create EC2 key pairs, and do not open port 22.

The EC2 instance configures itself through **EC2 user data (cloud-init)**. During first boot it clones this repository, installs Node.js 24, SQLite and Nginx, creates a systemd service for the Node.js backend, configures Nginx as a reverse proxy, and exposes the application on HTTP port 80.

## Architecture

```text
Student browser
      |
      | HTTP :80
      v
   Nginx on EC2
      |
      | localhost:5177
      v
 Node.js backend
      |
      v
 SQLite teaching database

AWS CloudShell
      |
      +-- AWS CLI: create / inspect / verify / clean up
      +-- curl: verify public HTTP API and SSE
      x-- no SSH / no SCP / no PEM key
```

This is a temporary teaching deployment. It intentionally uses HTTP on a public IPv4 address. A production deployment would normally add DNS, HTTPS/TLS, stronger access controls, managed data services, observability and high-availability design.

## Requirements

- Open AWS CloudShell from the teaching AWS Console session.
- Use the Region specified for the Week 11 lab (default: `ap-southeast-2`).
- Use the instance type specified for the current teaching environment (default in scripts: `t3.micro`).
- The AWS account must permit EC2, VPC/security-group inspection and creation, SSM public-parameter reads, and instance termination.

CloudShell supplies temporary AWS credentials from the Console session. Do not create or paste long-term AWS access keys.

## Student workflow

```bash
git clone https://github.com/CSE3CWA-5006/CSE3CWA-5006-Week-11.git
cd CSE3CWA-5006-Week-11/iot-smart-city/scripts
chmod +x *.sh

./01_cli_login_check.sh
OWNER="student-12345678" ./02_create_iot_ec2.sh
./03_wait_for_iot_app.sh
./04_verify_iot_site.sh
./05_inspect_iot_ec2.sh
./06_cleanup_iot_ec2.sh terminate
```

### Script responsibilities

| Script | Responsibility | Changes AWS? |
|---|---|---:|
| `01_cli_login_check.sh` | Verifies CloudShell identity, Region and current EC2 state. | No |
| `02_create_iot_ec2.sh` | Selects a public-capable subnet, creates/reuses an HTTP security group, resolves Ubuntu 24.04, launches EC2 with user data, and records deployment state. | Yes |
| `03_wait_for_iot_app.sh` | Polls the application-level bootstrap status until cloud-init finishes the installation. | No |
| `04_verify_iot_site.sh` | Verifies health, bootstrap data and Server-Sent Events from CloudShell over HTTP. | No |
| `05_inspect_iot_ec2.sh` | Shows EC2/network/security-group state and public application status. | No |
| `06_cleanup_iot_ec2.sh` | Terminates the instance, waits for termination, deletes a lab-created security group, and removes local deployment state. | Yes |

## Why no SSH is required

The deployment is intentionally designed around CloudShell. EC2 user data performs the operating-system and application configuration during first boot. This demonstrates an important automation principle: a server should be able to initialise from a declared bootstrap process rather than depending on a person logging in and configuring it interactively.

The security group therefore exposes only TCP port 80 for the temporary public teaching site. Port 22 is not opened and no EC2 key pair is created.

## Application components

- `public/` — browser interface.
- `server/server.mjs` — Node.js HTTP API and static-file server.
- `data/smart_city_iot.sqlite` — synthetic/anonymised teaching data.
- `scripts/` — CloudShell deployment and verification automation.

The backend exposes `/api/health`, `/api/bootstrap`, `/api/readings` and `/api/stream`. Nginx forwards public requests to Node.js on `127.0.0.1:5177`. The SSE route is configured with proxy buffering disabled so events can be delivered without proxy-induced delay.

## Deployment state and diagnostics

`02_create_iot_ec2.sh` writes non-secret deployment identifiers to:

```text
deployment/aws_iot_instance.env
```

The instance writes bootstrap output to:

```text
/var/log/week11-iot-bootstrap.log
```

Students do not log in to read that file. If bootstrap fails, use the EC2 Console system log for diagnosis. The public marker `/deployment-status.txt` contains only `BOOTSTRAPPING`, `READY` or `FAILED` and contains no credentials or internal paths.

## Verification

`04_verify_iot_site.sh` verifies the deployment from CloudShell rather than from inside the EC2 instance. It requires:

1. `/api/health` to return `ok: true`;
2. `/api/bootstrap` to return a non-empty response;
3. `/api/stream` to produce an expected SSE `init` or `tick` event.

This distinguishes infrastructure state (`EC2 is running`) from application readiness (`the deployed service is responding correctly`).

## Cleanup

Run:

```bash
./06_cleanup_iot_ec2.sh terminate
```

The script requires explicit `TERMINATE` confirmation, waits for EC2 termination, removes the security group only when the deployment recorded that it created the group, and removes local deployment state. No key pair or PEM file exists in this workflow.

`stop` is available only when the lecturer explicitly asks students to retain the instance:

```bash
./06_cleanup_iot_ec2.sh stop
```

Stopping is not cleanup: the instance and storage remain allocated.

## Data notice

All scenario information, map placement, sensor identifiers, coordinates, readings and related display data are synthetic, anonymised or relocated for teaching and software testing. They are not operational municipal or infrastructure records.

## Licence and copyright

Copyright (C) 2026 Shuo Ding

This project is licensed under the **GNU Affero General Public License version 3 only (`AGPL-3.0-only`)**. The licence permits use, study, modification and redistribution under its terms and includes source-code obligations for modified versions made available to users over a network.

See [`LICENSE`](LICENSE) for the complete GNU AGPL v3 text and [`NOTICE.md`](NOTICE.md) for the project copyright, attribution and teaching-data notice.
