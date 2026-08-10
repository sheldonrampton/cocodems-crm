#!/usr/bin/env bash
# Manage safety snapshots of staging (named full DB + files copies in S3).
#
# Run from your laptop (local .env, no SITE_DOMAIN):
#
#   bash scripts/staging-snapshot.sh create pre-wp-push
#   bash scripts/staging-snapshot.sh list
#   bash scripts/staging-snapshot.sh restore pre-wp-push --yes
#   bash scripts/staging-snapshot.sh delete pre-wp-push --yes
#
# Workflow for testing a risky staging script:
#
#   1. bash scripts/staging-snapshot.sh create pre-test
#   2. bash scripts/sync-local-wordpress-to-staging.sh --yes   # or other test
#   3a. OK  → bash scripts/staging-snapshot.sh delete pre-test --yes
#   3b. Bad → bash scripts/staging-snapshot.sh restore pre-test --yes
#
# Snapshots live under:
#   s3://BACKUP_S3_BUCKET/cocodems/snapshots/<name>/{manifest.json,database.sql.gz,files.tar.gz}
#
# Requires: BACKUP_S3_BUCKET, STAGING_EC2_INSTANCE_ID, AWS_REGION (for create/restore)
# and AWS credentials that can access the bucket and send SSM commands.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
COMMAND=""
SNAPSHOT_NAME=""
FORCE=0

usage() {
	cat <<'EOF'
Usage: staging-snapshot.sh <command> [name] [options]

  create <name>     Capture staging DB + files to S3 (via SSM)
  list              List snapshots in the backup bucket
  restore <name>    Overwrite staging from a named snapshot (via SSM)
  delete <name>     Delete a named snapshot from S3
  show <name>       Print snapshot manifest

  --yes, -y         Skip confirmation (restore/delete)

Snapshot names: 1–63 chars, [A-Za-z0-9._-], must start with alphanumeric.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--yes | -y)
			FORCE=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		create | list | restore | delete | show)
			COMMAND="$1"
			shift
			;;
		-*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
		*)
			if [[ -n "${SNAPSHOT_NAME}" ]]; then
				echo "Unexpected argument: $1" >&2
				exit 1
			fi
			SNAPSHOT_NAME="$1"
			shift
			;;
	esac
done

if [[ -z "${COMMAND}" ]]; then
	usage >&2
	exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	echo "Run this from your laptop local .env (not the staging server env)." >&2
	echo "On the server use create-/restore-staging-snapshot-on-server.sh directly." >&2
	exit 1
fi

BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
STAGING_EC2_INSTANCE_ID="$(read_env STAGING_EC2_INSTANCE_ID)"
AWS_REGION="$(read_env AWS_REGION)"
AWS_REGION="${AWS_REGION:-us-east-2}"

if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
	echo "Set BACKUP_S3_BUCKET in ${ENV_FILE}" >&2
	exit 1
fi
if ! command -v aws >/dev/null 2>&1; then
	echo "aws CLI is required." >&2
	exit 1
fi

validate_name() {
	if [[ -z "${SNAPSHOT_NAME}" ]]; then
		echo "Snapshot name required." >&2
		usage >&2
		exit 1
	fi
	if ! [[ "${SNAPSHOT_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$ ]]; then
		echo "Invalid snapshot name '${SNAPSHOT_NAME}'." >&2
		exit 1
	fi
}

require_ssm() {
	if [[ -z "${STAGING_EC2_INSTANCE_ID}" ]]; then
		echo "Set STAGING_EC2_INSTANCE_ID in ${ENV_FILE} for ${COMMAND}." >&2
		exit 1
	fi
}

wait_ssm() {
	local cmd_id="$1"
	local status="Pending"
	local i
	for i in $(seq 1 120); do
		status="$(
			aws ssm get-command-invocation \
				--region "${AWS_REGION}" \
				--command-id "${cmd_id}" \
				--instance-id "${STAGING_EC2_INSTANCE_ID}" \
				--query 'Status' \
				--output text 2>/dev/null || echo Pending
		)"
		if [[ "${status}" == "Success" ]]; then
			echo "${status}"
			return 0
		fi
		if [[ "${status}" == "Failed" || "${status}" == "Cancelled" || "${status}" == "TimedOut" ]]; then
			aws ssm get-command-invocation \
				--region "${AWS_REGION}" \
				--command-id "${cmd_id}" \
				--instance-id "${STAGING_EC2_INSTANCE_ID}" \
				--query '[Status,StandardOutputContent,StandardErrorContent]' \
				--output text >&2
			return 1
		fi
		sleep 5
	done
	echo "Timed out waiting for SSM (last status: ${status})." >&2
	return 1
}

run_ssm() {
	local remote_cmd="$1"
	local comment="$2"
	local params
	params="$(mktemp "${TMPDIR:-/tmp}/cocodems-ssm.XXXXXX.json")"
	python3 - "${remote_cmd}" "${params}" <<'PY'
import json, sys
cmd, path = sys.argv[1], sys.argv[2]
with open(path, "w") as f:
    json.dump({"commands": [cmd]}, f)
PY
	local cmd_id
	cmd_id="$(
		aws ssm send-command \
			--region "${AWS_REGION}" \
			--instance-ids "${STAGING_EC2_INSTANCE_ID}" \
			--document-name AWS-RunShellScript \
			--comment "${comment}" \
			--parameters "file://${params}" \
			--timeout-seconds 1800 \
			--output text \
			--query 'Command.CommandId'
	)"
	rm -f "${params}"
	echo "SSM command: ${cmd_id}"
	if ! wait_ssm "${cmd_id}"; then
		exit 1
	fi
	aws ssm get-command-invocation \
		--region "${AWS_REGION}" \
		--command-id "${cmd_id}" \
		--instance-id "${STAGING_EC2_INSTANCE_ID}" \
		--query 'StandardOutputContent' \
		--output text
}

case "${COMMAND}" in
	list)
		echo "Snapshots in s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/"
		# List "directories" then try manifest created_at
		aws s3 ls "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/" \
			| awk '/PRE / {print $2}' \
			| sed 's#/##' \
			| while IFS= read -r name; do
				[[ -z "${name}" || "${name}" == "latest.txt" ]] && continue
				created="$(
					aws s3 cp "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/${name}/manifest.json" - 2>/dev/null \
						| python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("created_at","?"), "contacts="+str(d.get("civicrm_contacts_live","?")))' \
						2>/dev/null || echo "(no manifest)"
				)"
				printf '  %-40s  %s\n' "${name}" "${created}"
			done
		if aws s3 ls "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/latest.txt" >/dev/null 2>&1; then
			echo "latest.txt → $(aws s3 cp "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/latest.txt" - 2>/dev/null | tr -d '\r\n')"
		fi
		;;
	show)
		validate_name
		aws s3 cp "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/${SNAPSHOT_NAME}/manifest.json" - \
			| python3 -m json.tool
		;;
	create)
		validate_name
		require_ssm
		echo "==> Creating snapshot '${SNAPSHOT_NAME}' on staging (${STAGING_EC2_INSTANCE_ID})..."
		run_ssm \
			"cd /opt/cocodems-crm && git pull --ff-only || true && bash scripts/create-staging-snapshot-on-server.sh ${SNAPSHOT_NAME}" \
			"Create staging safety snapshot ${SNAPSHOT_NAME}"
		echo ""
		echo "Create complete. Restore later with:"
		echo "  bash scripts/staging-snapshot.sh restore ${SNAPSHOT_NAME} --yes"
		;;
	restore)
		validate_name
		require_ssm
		if [[ ${FORCE} -ne 1 ]]; then
			echo "This OVERWRITES the live staging site from snapshot '${SNAPSHOT_NAME}'."
			echo "Type RESTORE_STAGING to continue:"
			if [[ -t 0 ]]; then
				printf '> ' >/dev/tty
				IFS= read -r confirm </dev/tty || confirm=""
			else
				IFS= read -r confirm || confirm=""
			fi
			confirm="$(printf '%s' "${confirm}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			if [[ "${confirm}" != "RESTORE_STAGING" ]]; then
				echo "Aborted." >&2
				exit 1
			fi
		fi
		echo "==> Restoring staging from snapshot '${SNAPSHOT_NAME}'..."
		run_ssm \
			"cd /opt/cocodems-crm && git pull --ff-only || true && bash scripts/restore-staging-snapshot-on-server.sh ${SNAPSHOT_NAME} --yes" \
			"Restore staging from safety snapshot ${SNAPSHOT_NAME}"
		echo ""
		echo "Restore complete."
		;;
	delete)
		validate_name
		if [[ ${FORCE} -ne 1 ]]; then
			echo "Delete S3 snapshot '${SNAPSHOT_NAME}'?"
			echo "Type DELETE_SNAPSHOT to continue:"
			if [[ -t 0 ]]; then
				printf '> ' >/dev/tty
				IFS= read -r confirm </dev/tty || confirm=""
			else
				IFS= read -r confirm || confirm=""
			fi
			confirm="$(printf '%s' "${confirm}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			if [[ "${confirm}" != "DELETE_SNAPSHOT" ]]; then
				echo "Aborted." >&2
				exit 1
			fi
		fi
		echo "==> Deleting s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/${SNAPSHOT_NAME}/..."
		aws s3 rm "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/${SNAPSHOT_NAME}/" --recursive
		# Clear latest pointer if it named this snapshot
		if aws s3 ls "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/latest.txt" >/dev/null 2>&1; then
			LATEST="$(aws s3 cp "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/latest.txt" - 2>/dev/null | tr -d '\r\n' || true)"
			if [[ "${LATEST}" == "${SNAPSHOT_NAME}" ]]; then
				aws s3 rm "s3://${BACKUP_S3_BUCKET}/cocodems/snapshots/latest.txt"
			fi
		fi
		echo "Deleted snapshot ${SNAPSHOT_NAME}."
		;;
	*)
		echo "Unknown command: ${COMMAND}" >&2
		usage >&2
		exit 1
		;;
esac
