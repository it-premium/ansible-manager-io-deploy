# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible deployment automation for **Manager.io** accounting software. Manages installation, upgrades, backup/restore across QA and Production environments. Hosts are resolved via Consul service discovery.

## Common Commands

### Deploy

```bash
# Production upgrade (downloads latest Manager.io release from GitHub, restarts service)
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventories/prod/hosts.ini app.yml

# QA upgrade
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventories/qa/hosts.ini app.yml

# Or via Makefile (uses pipenv)
make production
make staging
```

### Backup & Restore

```bash
# Trigger Nomad scheduled backup (runs restic snapshot to host volume)
nomad job periodic force volume-backup-manager

# Ansible-based backup to S3 (requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
ansible-playbook -i inventories/prod/hosts.ini backup.yml

# Restore from S3 backup
ansible-playbook -i inventories/prod/hosts.ini restore.yml -e backup_file=data-YYMMDD-HHMM.tar.gz
```

## Architecture

### Playbooks

| Playbook | Target Group | Purpose |
|----------|-------------|---------|
| `app.yml` | `app` | Main deployment: install deps, download release, create systemd service, restart |
| `backup.yml` | `manager` | Archive `/var/lib/manager` and upload to S3 (`manager.it-premium.local` bucket) |
| `restore.yml` | `app` | Stop service, restore data from S3 backup, restart |
| `nginx.yml` | `nginx` | Deploy nginx reverse proxy config, validate, reload |

### Environments

- **Production**: `inventories/prod/hosts.ini` — host `prod-manager.node.consul`, user `itpremium`
- **QA**: `inventories/qa/hosts.ini` — host `qa-manager.node.consul`, user `itpremium`

### Key Paths on Target Hosts

- Application: `/usr/share/manager`
- Data: `/var/lib/manager`
- Local backups: `/var/backups/manager`
- Systemd service: `/etc/systemd/system/manager-server.service` (from `templates/manager-server.service.j2`)

### CI/CD (Jenkins)

- `Jenkinsfile` — Deploy + optional restore (params: `DEPLOY_ENV`, `RESTORE`)
- `Jenkinsfile.backup` — Backup to S3 (param: `DEPLOY_ENV`)
- `Jenkinsfile.restore` — Restore from S3 with backup file selection

Jenkins credentials: `jenkins-ssh-core` (SSH), `manager-credentials` (AWS S3).

### Backup Strategy

Two backup mechanisms exist:
1. **Nomad periodic job** (`volume-backup-manager`): runs daily at 23:58 UTC, uses restic, keeps last 24 snapshots
2. **Ansible playbook** (`backup.yml`): archives data to S3 via Jenkins pipeline
