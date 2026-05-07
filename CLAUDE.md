# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible deployment automation for **Manager.io** accounting software. Manages installation, upgrades, backup/restore across QA and Production environments. Hosts are resolved via Consul service discovery.

## Common Commands

### One-time setup

```bash
# Install Python deps (ansible-core, boto3, python-consul) and Ansible collections
make bootstrap
```

`make bootstrap` runs `uv sync` (creates `.venv` from `pyproject.toml` / `uv.lock`) and installs Ansible collections from `requirements.yml`.

### Deploy

```bash
# QA upgrade
make staging

# Production upgrade
make production

# Or directly (skipping the Makefile / uv wrapper)
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventories/qa/hosts.ini app.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventories/prod/hosts.ini app.yml
```

Both `make` targets shell out to `uv run -- ansible-playbook ...` against the matching inventory.

### Backup & Restore (Nomad/Restic — Recommended)

```bash
# 1. Trigger fresh prod backup
nomad job periodic force volume-backup-manager

# 2. Check logs for snapshot ID
nomad alloc logs <ALLOC_ID>
# Output: "snapshot 526593c4 saved"

# 3. Restore to QA (stops service, restores, starts service automatically)
nomad job dispatch -meta snapshot_id=<SNAPSHOT_ID> volume-restore-manager
```

Nomad job files live in `../nomad/manager-backup.nomad` and `../nomad/manager-restore.nomad`.
Vault secrets use workload identity (Nomad 1.9+) via `kv/data/default/volume-restore-manager/backups`.

### Backup & Restore (Ansible — Legacy)

```bash
# Backup to S3 (requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
ansible-playbook -i inventories/prod/hosts.ini backup.yml

# Restore from S3 (note: S3 download step in restore.yml is commented out, manual transfer needed)
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
- **QA**: `inventories/qa/hosts.ini` — host `qa-manager.node.consul`, user `itpremium` (also contains a legacy `[old]` group pointing at a CentOS host — unused by `app.yml`)

Variable defaults live in `group_vars/all.yml` (port, paths, consul service name, firewalld toggle).

### Key Paths on Target Hosts

- Application: `/usr/share/manager`
- Data: `/var/lib/manager`
- Local backups: `/var/backups/manager` — pre-upgrade binary archives land here as `<iso8601_basic_short>.tgz` (e.g. `20260507T084012Z.tgz`)
- Systemd service: `/etc/systemd/system/manager-server.service` (from `templates/manager-server.service.j2`)
- Service port: `8080` (from `manager_port` in `group_vars/all.yml`)

### CI/CD (Jenkins)

- `Jenkinsfile` — Deploy + optional restore (params: `DEPLOY_ENV`, `RESTORE`)
- `Jenkinsfile.backup` — Backup to S3 (param: `DEPLOY_ENV`)
- `Jenkinsfile.restore` — Restore from S3 with backup file selection

Jenkins credentials: `jenkins-ssh-core` (SSH), `manager-credentials` (AWS S3).

### Backup Strategy

Two backup mechanisms exist:
1. **Nomad periodic job** (`volume-backup-manager`): runs daily at 23:58 UTC, uses restic to S3 bucket `it-premium-infra-backups`, keeps last 24 snapshots. Restore job (`volume-restore-manager`) is parameterized and targets QA node pool.
2. **Ansible playbook** (`backup.yml`): archives data as tar.gz to S3 bucket `manager.it-premium.local` via Jenkins pipeline

Prod→QA replication uses the Nomad approach: backup prod snapshot, then dispatch restore to QA with the snapshot ID.

## Gotchas

- **No version pinning.** `app.yml` extracts from `https://github.com/Manager-io/Manager/releases/latest/download/ManagerServer-linux-x64.tar.gz`, so each run re-resolves `latest`. QA verification does NOT pin what production will get if Manager.io ships a release between the two runs. Resolve the current `latest` tag with:

  ```bash
  curl -sI https://github.com/Manager-io/Manager/releases/latest | grep -i location
  ```

- **Pre-upgrade backup is the binary, not the data.** `app.yml` archives `/usr/share/manager` → `/var/backups/manager/<timestamp>.tgz` before each run. Useful for fast rollback of the binary, but data-level protection is the Nomad/restic flow above.

- **`restore.yml` S3 download step is commented out.** You must scp the tarball to `/tmp/<backup_file>` on the host before running `ansible-playbook ... restore.yml -e backup_file=...`.

- **`nginx.yml` references `app.domain`** which is not defined in `group_vars/all.yml`. Pass it via `-e app.domain=...` or extend group_vars before running.
