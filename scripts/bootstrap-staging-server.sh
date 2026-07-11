#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu 22.04 EC2 instance for CoCoDems staging.
# Run on the server as root (or via sudo).
#
#   curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/cocodems-crm/main/scripts/bootstrap-staging-server.sh | sudo bash
#   # or after cloning:
#   sudo bash scripts/bootstrap-staging-server.sh

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating packages..."
apt-get update -qq
apt-get upgrade -y -qq

echo "==> Installing Docker..."
apt-get install -y -qq ca-certificates curl gnupg git nginx apache2-utils gettext-base

if ! command -v docker >/dev/null 2>&1; then
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	chmod a+r /etc/apt/keyrings/docker.gpg
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
		> /etc/apt/sources.list.d/docker.list
	apt-get update -qq
	apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

echo "==> Installing Certbot..."
apt-get install -y -qq certbot python3-certbot-nginx

echo "==> Installing AWS CLI (S3 backups via scripts/backup-db.sh --upload)..."
apt-get install -y -qq awscli

echo "==> Adding ubuntu user to docker group..."
usermod -aG docker ubuntu || true

echo "==> Enabling services..."
systemctl enable docker nginx
systemctl start docker

# Remove default nginx site if present (often causes empty replies on port 80).
rm -f /etc/nginx/sites-enabled/default

echo "==> Bootstrap complete."
echo "Next: deploy the application as the ubuntu user:"
echo "  sudo -u ubuntu bash /opt/cocodems-crm/scripts/deploy-staging.sh"
echo "After deploy and BACKUP_S3_BUCKET in .env:"
echo "  sudo bash /opt/cocodems-crm/scripts/setup-staging-backup-cron.sh"
echo "Or clone the repo first — see docs/deployment.md"
