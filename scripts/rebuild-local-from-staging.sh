#!/usr/bin/env bash
# Wipe and rebuild the local Docker stack to match staging as closely as practical.
#
#   bash scripts/rebuild-local-from-staging.sh
#   bash scripts/rebuild-local-from-staging.sh --yes
#   bash scripts/rebuild-local-from-staging.sh --yes --skip-files
#
# What it does:
#   1. Reads WordPress + CiviCRM versions from S3 (or uses .env pins)
#   2. Optionally refreshes the staging files archive via SSM
#   3. docker compose down -v  (destroys local DB + WordPress volumes)
#   4. Rebuilds PHP image with matching WORDPRESS_VERSION / CIVICRM_VERSION
#   5. Waits for first-time install
#   6. Restores latest staging DB (sync-staging-to-local.sh)
#   7. Extracts staging plugins + CiviCRM ext/custom/persist files
#
# Requirements (local .env):
#   BACKUP_S3_BUCKET
#   CIVICRM_UF_BASEURL=http://localhost:8080
#   no SITE_DOMAIN
# Optional:
#   STAGING_EC2_INSTANCE_ID  (to refresh files archive via SSM before rebuild)
#   AWS_REGION=us-east-2
#   WORDPRESS_VERSION / CIVICRM_VERSION (override discovered versions)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
FORCE=0
SKIP_FILES=0
SKIP_DB=0
REFRESH_FILES=0

usage() {
	cat <<'EOF'
Usage: rebuild-local-from-staging.sh [options]

  --yes             Skip confirmation
  --skip-files      Do not download/extract the staging files archive
  --skip-db         Do not restore the staging database
  --refresh-files   Run backup-staging-files.sh --upload on staging via SSM first
                    (requires STAGING_EC2_INSTANCE_ID)
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
		--refresh-files)
			REFRESH_FILES=1
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

read_env() {
	local key="$1"
	grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//' || true
}

set_env_key() {
	local key="$1"
	local value="$2"
	if grep -qE "^${key}=" "${ENV_FILE}"; then
		# Portable in-place replace without baking secrets into sed separators badly.
		python3 - "${ENV_FILE}" "${key}" "${value}" <<'PY'
import pathlib, sys
path, key, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines()
out = []
found = False
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={value}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
PY
	else
		printf '\n%s=%s\n' "${key}" "${value}" >>"${ENV_FILE}"
	fi
}

if [[ ! -f "${ENV_FILE}" ]]; then
	echo "Missing ${ENV_FILE}. Copy .env.example to .env first." >&2
	exit 1
fi

if grep -q '^SITE_DOMAIN=' "${ENV_FILE}" 2>/dev/null; then
	echo "This script is for the local laptop only (remove SITE_DOMAIN from .env)." >&2
	exit 1
fi

BACKUP_S3_BUCKET="$(read_env BACKUP_S3_BUCKET)"
AWS_REGION="$(read_env AWS_REGION)"
AWS_REGION="${AWS_REGION:-us-east-2}"
STAGING_EC2_INSTANCE_ID="$(read_env STAGING_EC2_INSTANCE_ID)"
COMPOSE="docker compose --project-directory ${REPO_ROOT} -f docker/docker-compose.yml -f docker/docker-compose.local.yml"

if [[ -z "${BACKUP_S3_BUCKET}" ]]; then
	echo "Set BACKUP_S3_BUCKET in ${ENV_FILE}" >&2
	exit 1
fi

if [[ ${FORCE} -ne 1 ]]; then
	echo "This will DESTROY local Docker volumes (WordPress files + MariaDB) and rebuild"
	echo "to match staging versions/plugins/database as closely as possible."
	read -r -p "Type REBUILD to continue: " confirm
	if [[ "${confirm}" != "REBUILD" ]]; then
		echo "Aborted."
		exit 1
	fi
fi

if [[ ${REFRESH_FILES} -eq 1 ]]; then
	if [[ -z "${STAGING_EC2_INSTANCE_ID}" ]]; then
		echo "Set STAGING_EC2_INSTANCE_ID in ${ENV_FILE} for --refresh-files" >&2
		exit 1
	fi
	if ! command -v aws >/dev/null 2>&1; then
		echo "aws CLI is required for --refresh-files" >&2
		exit 1
	fi
	echo "==> Refreshing staging files archive via SSM (${STAGING_EC2_INSTANCE_ID})..."
	CMD_ID="$(
		aws ssm send-command \
			--region "${AWS_REGION}" \
			--instance-ids "${STAGING_EC2_INSTANCE_ID}" \
			--document-name AWS-RunShellScript \
			--parameters 'commands=["cd /opt/cocodems-crm && git pull --ff-only || true && bash scripts/backup-staging-files.sh --upload"]' \
			--output text \
			--query 'Command.CommandId'
	)"
	echo "SSM command: ${CMD_ID}"
	for _ in $(seq 1 60); do
		STATUS="$(aws ssm get-command-invocation --region "${AWS_REGION}" --command-id "${CMD_ID}" --instance-id "${STAGING_EC2_INSTANCE_ID}" --query 'Status' --output text 2>/dev/null || echo Pending)"
		if [[ "${STATUS}" == "Success" ]]; then
			break
		fi
		if [[ "${STATUS}" == "Failed" || "${STATUS}" == "Cancelled" || "${STATUS}" == "TimedOut" ]]; then
			aws ssm get-command-invocation --region "${AWS_REGION}" --command-id "${CMD_ID}" --instance-id "${STAGING_EC2_INSTANCE_ID}" --query '[Status,StandardOutputContent,StandardErrorContent]' --output text >&2
			exit 1
		fi
		sleep 5
	done
	if [[ "${STATUS}" != "Success" ]]; then
		echo "Timed out waiting for staging files backup." >&2
		exit 1
	fi
	echo "Staging files archive refreshed."
fi

WP_VERSION="$(read_env WORDPRESS_VERSION)"
CIVI_VERSION="$(read_env CIVICRM_VERSION)"

if [[ ${SKIP_FILES} -eq 0 ]] || [[ -z "${WP_VERSION}" || -z "${CIVI_VERSION}" ]]; then
	echo "==> Reading staging versions from s3://${BACKUP_S3_BUCKET}/cocodems/files/versions.json..."
	if aws s3 cp "s3://${BACKUP_S3_BUCKET}/cocodems/files/versions.json" /tmp/cocodems-versions.json >/dev/null 2>&1; then
		DISCOVERED_WP="$(python3 -c 'import json; print(json.load(open("/tmp/cocodems-versions.json")).get("wordpress",""))')"
		DISCOVERED_CIVI="$(python3 -c 'import json; print(json.load(open("/tmp/cocodems-versions.json")).get("civicrm",""))')"
		[[ -z "${WP_VERSION}" && -n "${DISCOVERED_WP}" ]] && WP_VERSION="${DISCOVERED_WP}"
		[[ -z "${CIVI_VERSION}" && -n "${DISCOVERED_CIVI}" ]] && CIVI_VERSION="${DISCOVERED_CIVI}"
	elif [[ ${SKIP_FILES} -eq 0 ]]; then
		echo "No files/versions.json in S3 yet. Run on staging:" >&2
		echo "  bash scripts/backup-staging-files.sh --upload" >&2
		echo "Or re-run with --refresh-files (needs STAGING_EC2_INSTANCE_ID)." >&2
		exit 1
	fi
fi

CIVI_VERSION="${CIVI_VERSION:-6.16.0}"
if [[ -z "${WP_VERSION}" ]]; then
	echo "Set WORDPRESS_VERSION in .env (e.g. 7.0.1) or create an S3 versions.json from staging." >&2
	exit 1
fi

echo "==> Pinning local build versions:"
echo "  WORDPRESS_VERSION=${WP_VERSION}"
echo "  CIVICRM_VERSION=${CIVI_VERSION}"
set_env_key WORDPRESS_VERSION "${WP_VERSION}"
set_env_key CIVICRM_VERSION "${CIVI_VERSION}"

echo "==> Destroying local volumes..."
${COMPOSE} down -v

echo "==> Building and starting with staging versions..."
${COMPOSE} up -d --build

echo "==> Waiting for first-time WordPress + CiviCRM install..."
for i in $(seq 1 90); do
	if ${COMPOSE} exec -T php test -f /var/www/private/wp-config.php 2>/dev/null; then
		echo "Install config found (${i})."
		break
	fi
	echo "Still installing... (${i}/90)"
	sleep 5
done

if ! ${COMPOSE} exec -T php test -f /var/www/private/wp-config.php 2>/dev/null; then
	echo "Timed out waiting for local install." >&2
	exit 1
fi

# Extra settle time for CiviCRM install to finish writing settings.
sleep 5

if [[ ${SKIP_DB} -eq 0 ]]; then
	echo "==> Restoring staging database..."
	bash "${REPO_ROOT}/scripts/sync-staging-to-local.sh" --yes
fi

if [[ ${SKIP_FILES} -eq 0 ]]; then
	echo "==> Downloading staging files archive..."
	TMP_TAR="$(mktemp "${TMPDIR:-/tmp}/cocodems-files.XXXXXX.tar.gz")"
	aws s3 cp "s3://${BACKUP_S3_BUCKET}/cocodems/files/latest.tar.gz" "${TMP_TAR}"
	echo "==> Extracting plugins and CiviCRM files into local WordPress..."
	${COMPOSE} cp "${TMP_TAR}" php:/tmp/staging-files.tar.gz
	${COMPOSE} exec -T php bash -c '
set -euo pipefail
# Extract into a temp dir, then merge. Never untar onto wp-content directly —
# archives store "./" as mode 0700 (from mktemp), which makes wp-content
# unreadable to www-data and causes "Plugin file does not exist".
EXTRACT=$(mktemp -d)
tar -xzf /tmp/staging-files.tar.gz -C "$EXTRACT"
rm -f /tmp/staging-files.tar.gz "$EXTRACT/versions.json"
mkdir -p /var/www/html/wp-content/plugins /var/www/html/wp-content/uploads/civicrm
if [ -d "$EXTRACT/plugins" ]; then
  cp -a "$EXTRACT/plugins"/. /var/www/html/wp-content/plugins/
fi
if [ -d "$EXTRACT/uploads/civicrm" ]; then
  cp -a "$EXTRACT/uploads/civicrm"/. /var/www/html/wp-content/uploads/civicrm/
fi
rm -rf "$EXTRACT"
chown -R www-data:www-data /var/www/html/wp-content
find /var/www/html/wp-content -type d -exec chmod 755 {} \;
chmod -R u+rwX,g+rwX /var/www/html/wp-content/uploads/civicrm
'
	rm -f "${TMP_TAR}"
fi

echo "==> Ensuring CiviCRM plugin matches image and DB is upgraded if needed..."
bash "${REPO_ROOT}/scripts/upgrade-civicrm.sh" || true

echo "==> Activating core plugins..."
${COMPOSE} exec -T php wp plugin activate civicrm cocodems-custom --allow-root --path=/var/www/html

echo "==> Flushing caches..."
${COMPOSE} exec -T -u www-data -e XDG_STATE_HOME=/var/www/private/.cv-state php cv flush 2>/dev/null || true
${COMPOSE} exec -T php wp cache flush --allow-root --path=/var/www/html 2>/dev/null || true

echo ""
echo "Local rebuild from staging complete."
echo "  WordPress: ${WP_VERSION}"
echo "  CiviCRM:   ${CIVI_VERSION}"
echo "  Site:      $(read_env CIVICRM_UF_BASEURL)"
echo "  Login:     $(read_env CIVICRM_UF_BASEURL)/wp-login.php"
echo "  User:      $(read_env CIVICRM_ADMIN_USER) / CIVICRM_ADMIN_PASS from .env"
echo ""
echo "cocodems-custom and cocodems-theme still come from your git checkout (bind mounts)."
