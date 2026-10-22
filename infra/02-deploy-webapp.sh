#!/usr/bin/env bash
# Phase 2 — deploy webapp/ to the backend VM with az vm run-command (no SSH).
# Installs Ubuntu's python3-flask + gunicorn packages, copies app.py and the
# systemd unit, (re)starts the service and checks /health from inside the VM.
set -euo pipefail
source "$(dirname "$0")/common.sh"

APP_B64="$(gzip -c "$REPO_ROOT/webapp/app.py" | base64 -w0)"
UNIT_B64="$(gzip -c "$REPO_ROOT/webapp/atdr-portal.service" | base64 -w0)"

SCRIPT="$(mktemp)"
trap 'rm -f "$SCRIPT"' EXIT
cat > "$SCRIPT" <<EOF
set -e
export DEBIAN_FRONTEND=noninteractive
if ! dpkg -s python3-flask gunicorn >/dev/null 2>&1; then
  apt-get update -q >/dev/null
  apt-get install -y -q python3-flask gunicorn >/dev/null
fi
id atdr >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin atdr
install -d -o root -g atdr -m 0750 /opt/atdr
echo "$APP_B64" | base64 -d | gunzip > /opt/atdr/app.py
chown root:atdr /opt/atdr/app.py && chmod 0640 /opt/atdr/app.py
echo "$UNIT_B64" | base64 -d | gunzip > /etc/systemd/system/atdr-portal.service
# gunicorn from apt would otherwise not be able to bind :80 if a default web server exists
systemctl disable --now nginx apache2 >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable atdr-portal >/dev/null 2>&1
systemctl restart atdr-portal
sleep 3
echo "service: \$(systemctl is-active atdr-portal)"
echo "versions: python \$(python3 -V 2>&1 | cut -d' ' -f2), flask \$(python3 -c 'import flask,importlib.metadata as m;print(m.version("flask"))'), gunicorn \$(gunicorn --version 2>&1 | awk '{print \$3}' | tr -d ')')"
echo "health: \$(curl -s -w ' HTTP %{http_code}' http://localhost/health)"
EOF

echo "[$(utc_now)] Deploying webapp to $VM_NAME via run-command"
az vm run-command invoke -g "$RG" -n "$VM_NAME" --command-id RunShellScript \
  --scripts @"$(winpath "$SCRIPT")" --query "value[0].message" -o tsv
