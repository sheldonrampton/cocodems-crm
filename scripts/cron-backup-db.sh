#!/usr/bin/env bash
# Cron entrypoint for backup-db.sh.
#
# Cron runs without login shells, so the ubuntu user may not have the docker
# group. This wrapper uses sg(1) to run the backup with docker access.
#
# Installed by scripts/setup-staging-backup-cron.sh — do not run manually unless
# testing: bash scripts/cron-backup-db.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

LOG_FILE="${COCODEMS_BACKUP_LOG:-/var/log/cocodems-backup.log}"

{
	echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) backup start ==="
	sg docker -c "bash ${REPO_ROOT}/scripts/backup-db.sh --upload"
	echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) backup done ==="
} >>"${LOG_FILE}" 2>&1
