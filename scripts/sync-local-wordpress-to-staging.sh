#!/usr/bin/env bash
# Push local WordPress content, plugins, theme, and configuration to staging
# without replacing CiviCRM contacts or other CiviCRM data objects on staging.
#
# Run on your laptop with the local stack running:
#
#   bash scripts/sync-local-wordpress-to-staging.sh
#   bash scripts/sync-local-wordpress-to-staging.sh --yes
#
# Requires:
#   - Local Docker stack (docker-compose.local.yml)
#   - .env with CIVICRM_UF_BASEURL=http://localhost:… (no SITE_DOMAIN)
#   - BACKUP_S3_BUCKET, STAGING_EC2_INSTANCE_ID, AWS_REGION
#   - AWS credentials that can write the backup bucket and send SSM commands
#
# What is pushed:
#   - All wp_* database tables (posts, options, users, menus, …)
#   - wp-content/plugins (except the civicrm plugin tree — staging keeps its CiviCRM install)
#   - wp-content/themes
#
# What is left on staging:
#   - All civicrm_*, log_civicrm_*, snap_civicrm_* tables
#   - uploads/civicrm (extensions data, custom files, etc.)
#
# Compatible with macOS Bash 3.2.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
FORCE=0
SKIP_FILES=0
SKIP_DB=0
TMP_DIR=""
WORK_DIR=""

cleanup() {
	if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
		rm -rf "${TMP_DIR}"
	fi
	if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
		rm -rf "${WORK_DIR}"
	fi
}
trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: sync-local-wordpress-to-staging.sh [options]

  Package local WordPress DB tables + plugins/themes, upload to S3, and apply
  on staging via SSM. CiviCRM data on staging is not replaced.

  --yes, -y       Skip confirmation prompt
  --skip-files    Push database tables only
  --skip-db       Push plugins/themes only
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--yes | -y)
			FORCE=1
			shift
			;;
		--skip-files)
			SKIP_FILES=1
			shift
			;;
		--skip-db)
			SKIP_DB=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
done

if [[ ${SKIP_FILES} -eq 1 && ${SKIP_DB} -eq 1 ]]; then
	echo "Nothing to do (--skip-files and --skip-db)." >&2
	exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}" >&2
	echo "Copy .env.example to .env for local development first." >&2
	exit 1
fi

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

if grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	echo "This script is for the local laptop only." >&2
	echo "${ENV_FILE} has SITE_DOMAIN set. Use a local .env from .env.example." >&2
	exit 1
fi

BASE_URL="$(read_env CIVICRM_UF_BASEURL)"
BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
MYSQL_DATABASE="$(read_env MYSQL_DATABASE)"
MYSQL_DATABASE="${MYSQL_DATABASE:-cocodems}"
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"
STAGING_EC2_INSTANCE_ID="$(read_env STAGING_EC2_INSTANCE_ID)"
AWS_REGION="$(read_env AWS_REGION)"
AWS_REGION="${AWS_REGION:-us-east-2}"
STAGING_SITE_URL="$(read_env STAGING_SITE_URL)"

if [[ -z "${BASE_URL}" ]]; then
	echo "Set CIVICRM_UF_BASEURL in ${ENV_FILE}" >&2
	exit 1
fi
if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
	echo "Set MYSQL_ROOT_PASSWORD in ${ENV_FILE}" >&2
	exit 1
fi
if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
	echo "Set BACKUP_S3_BUCKET in ${ENV_FILE}" >&2
	exit 1
fi
if [[ -z "${STAGING_EC2_INSTANCE_ID}" ]]; then
	echo "Set STAGING_EC2_INSTANCE_ID in ${ENV_FILE} (staging EC2 instance id)." >&2
	exit 1
fi
if ! command -v aws >/dev/null 2>&1; then
	echo "aws CLI is required." >&2
	exit 1
fi

COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"

if ! ${COMPOSE} exec -T mariadb true 2>/dev/null; then
	echo "Local MariaDB is not running. Start the stack first." >&2
	exit 1
fi
if ! ${COMPOSE} exec -T php true 2>/dev/null; then
	echo "Local PHP container is not running. Start the stack first." >&2
	exit 1
fi

if [[ ${FORCE} -ne 1 ]]; then
	echo "This will REPLACE WordPress tables + plugins/themes on staging"
	echo "from this laptop's local Docker site (${BASE_URL})."
	echo "CiviCRM contacts and other CiviCRM data on staging will NOT be modified."
	if [[ -n "${STAGING_SITE_URL}" ]]; then
		echo "Target: ${STAGING_SITE_URL} (instance ${STAGING_EC2_INSTANCE_ID})"
	else
		echo "Target instance: ${STAGING_EC2_INSTANCE_ID}"
	fi
	echo "Or re-run with --yes to skip this prompt."
	if [[ -t 0 ]]; then
		printf 'Type PUSH_WP to continue: ' >/dev/tty
		IFS= read -r confirm </dev/tty || confirm=""
	else
		printf 'Type PUSH_WP to continue: '
		IFS= read -r confirm || confirm=""
	fi
	confirm="$(printf '%s' "${confirm}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	if [[ "${confirm}" != "PUSH_WP" ]]; then
		echo "Aborted (expected PUSH_WP, got: ${confirm:-<empty>})." >&2
		echo "Tip: bash scripts/sync-local-wordpress-to-staging.sh --yes" >&2
		exit 1
	fi
fi

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
S3_PREFIX="cocodems/sync/local-wp/${TIMESTAMP}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cocodems-wp-push.XXXXXX")"

mysql_root() {
	${COMPOSE} exec -T -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" mariadb \
		sh -ec 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$@"' -- "$@"
}

echo "==> Detecting WordPress table prefix..."
TABLE_PREFIX="$(
	${COMPOSE} exec -T php wp config get table_prefix --allow-root --path=/var/www/html 2>/dev/null | tr -d '\r' || true
)"
TABLE_PREFIX="${TABLE_PREFIX:-wp_}"

WP_TABLE_LIST="$(
	mysql_root -N -e "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = '${MYSQL_DATABASE}'
  AND table_name LIKE CONCAT(REPLACE('${TABLE_PREFIX}', '_', '\\\\_'), '%') ESCAPE '\\\\'
ORDER BY table_name;
" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
)"

if [[ -z "${WP_TABLE_LIST}" ]]; then
	echo "No WordPress tables matching prefix '${TABLE_PREFIX}' in ${MYSQL_DATABASE}." >&2
	exit 1
fi

WP_TABLE_COUNT="$(printf '%s\n' ${WP_TABLE_LIST} | wc -l | tr -d ' ')"
echo "    ${WP_TABLE_COUNT} table(s) with prefix ${TABLE_PREFIX}"

cat >"${WORK_DIR}/manifest.json" <<EOF
{
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "local_base_url": "${BASE_URL}",
  "table_prefix": "${TABLE_PREFIX}",
  "wordpress_tables": ${WP_TABLE_COUNT},
  "skip_db": ${SKIP_DB},
  "skip_files": ${SKIP_FILES}
}
EOF

if [[ ${SKIP_DB} -eq 0 ]]; then
	echo "==> Dumping local WordPress tables..."
	# shellcheck disable=SC2086
	if ! ${COMPOSE} exec -T \
		-e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
		-e "MYSQL_DATABASE=${MYSQL_DATABASE}" \
		-e "TABLE_LIST=${WP_TABLE_LIST}" \
		mariadb sh -ec '
			# shellcheck disable=SC2086
			mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
				--single-transaction \
				--routines=false \
				--triggers \
				"$MYSQL_DATABASE" $TABLE_LIST
		' | gzip -9 >"${WORK_DIR}/wp-tables.sql.gz"; then
		echo "mysqldump of WordPress tables failed." >&2
		exit 1
	fi
	echo "    $(du -h "${WORK_DIR}/wp-tables.sql.gz" | awk '{print $1}')"
else
	# Empty placeholder so apply always has a file if we skip (apply requires all three;
	# when skip-db we still need apply to skip import — pass flag in manifest, apply reads it)
	gzip -c </dev/null >"${WORK_DIR}/wp-tables.sql.gz"
fi

if [[ ${SKIP_FILES} -eq 0 ]]; then
	echo "==> Packaging plugins and themes (excluding civicrm plugin)..."
	${COMPOSE} exec -T php bash -c '
set -euo pipefail
TMP=$(mktemp -d)
chmod 755 "$TMP"
mkdir -p "$TMP/plugins" "$TMP/themes"
cd /var/www/html/wp-content
if [ -d plugins ]; then
  find plugins -mindepth 1 -maxdepth 1 ! -name civicrm -exec cp -a {} "$TMP/plugins/" \;
fi
if [ -d themes ]; then
  find themes -mindepth 1 -maxdepth 1 -exec cp -a {} "$TMP/themes/" \;
fi
tar -czf /tmp/cocodems-wp-content.tar.gz -C "$TMP" .
rm -rf "$TMP"
'
	${COMPOSE} cp php:/tmp/cocodems-wp-content.tar.gz "${WORK_DIR}/wp-content.tar.gz"
	${COMPOSE} exec -T php rm -f /tmp/cocodems-wp-content.tar.gz
	echo "    $(du -h "${WORK_DIR}/wp-content.tar.gz" | awk '{print $1}')"
else
	# Minimal empty archive
	EMPTY="$(mktemp -d)"
	tar -czf "${WORK_DIR}/wp-content.tar.gz" -C "${EMPTY}" .
	rm -rf "${EMPTY}"
fi

echo "==> Uploading package to s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/..."
aws s3 cp "${WORK_DIR}/manifest.json" "s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/manifest.json"
aws s3 cp "${WORK_DIR}/wp-tables.sql.gz" "s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/wp-tables.sql.gz"
aws s3 cp "${WORK_DIR}/wp-content.tar.gz" "s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/wp-content.tar.gz"
# Pointer for operators
echo "${S3_PREFIX}" | aws s3 cp - "s3://${BACKUP_S3_BUCKET}/cocodems/sync/local-wp/latest.txt"

PACKAGE_URI="s3://${BACKUP_S3_BUCKET}/${S3_PREFIX}/"
echo "Package: ${PACKAGE_URI}"

echo "==> Applying on staging via SSM (${STAGING_EC2_INSTANCE_ID})..."
SSM_PARAMS="$(mktemp "${TMPDIR:-/tmp}/cocodems-ssm-params.XXXXXX.json")"
python3 - "${PACKAGE_URI}" "${SSM_PARAMS}" <<'PY'
import json, sys
uri = sys.argv[1]
path = sys.argv[2]
cmd = (
    "cd /opt/cocodems-crm && git pull --ff-only || true && "
    "bash scripts/apply-local-wordpress-on-staging.sh " + uri
)
with open(path, "w") as f:
    json.dump({"commands": [cmd]}, f)
PY

CMD_ID="$(
	aws ssm send-command \
		--region "${AWS_REGION}" \
		--instance-ids "${STAGING_EC2_INSTANCE_ID}" \
		--document-name AWS-RunShellScript \
		--comment "Apply local WordPress package to staging (CiviCRM preserved)" \
		--parameters "file://${SSM_PARAMS}" \
		--timeout-seconds 1800 \
		--output text \
		--query 'Command.CommandId'
)"
rm -f "${SSM_PARAMS}"
echo "SSM command: ${CMD_ID}"

STATUS="Pending"
for _ in $(seq 1 120); do
	STATUS="$(
		aws ssm get-command-invocation \
			--region "${AWS_REGION}" \
			--command-id "${CMD_ID}" \
			--instance-id "${STAGING_EC2_INSTANCE_ID}" \
			--query 'Status' \
			--output text 2>/dev/null || echo Pending
	)"
	if [[ "${STATUS}" == "Success" ]]; then
		break
	fi
	if [[ "${STATUS}" == "Failed" || "${STATUS}" == "Cancelled" || "${STATUS}" == "TimedOut" ]]; then
		echo "SSM command ${STATUS}:" >&2
		aws ssm get-command-invocation \
			--region "${AWS_REGION}" \
			--command-id "${CMD_ID}" \
			--instance-id "${STAGING_EC2_INSTANCE_ID}" \
			--query '[Status,StandardOutputContent,StandardErrorContent]' \
			--output text >&2
		exit 1
	fi
	sleep 5
done

if [[ "${STATUS}" != "Success" ]]; then
	echo "Timed out waiting for staging apply (last status: ${STATUS})." >&2
	exit 1
fi

echo ""
echo "==> Staging output:"
aws ssm get-command-invocation \
	--region "${AWS_REGION}" \
	--command-id "${CMD_ID}" \
	--instance-id "${STAGING_EC2_INSTANCE_ID}" \
	--query 'StandardOutputContent' \
	--output text

echo ""
echo "Local → staging WordPress sync complete."
echo "  Package: ${PACKAGE_URI}"
if [[ -n "${STAGING_SITE_URL}" ]]; then
	echo "  Site:    ${STAGING_SITE_URL%/}/wp-login.php"
fi
echo "CiviCRM data on staging was not replaced. Log in with local WordPress credentials."
