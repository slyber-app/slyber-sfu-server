#!/usr/bin/env bash
set -euo pipefail

SERVICE_USER="slyber_sfu"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERR] This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "[INFO] Stopping and removing slyber_sfu service..."
systemctl stop slyber_sfu 2>/dev/null || true
systemctl disable slyber_sfu 2>/dev/null || true
rm -f /etc/systemd/system/slyber_sfu.service
systemctl daemon-reload

rm -f /usr/local/bin/slyber_sfu
rm -f /opt/slyber_sfu/slyber_sfu

if [ "${PURGE_DATA:-false}" = "true" ]; then
    rm -rf /opt/slyber_sfu
    if id -u "${SERVICE_USER}" >/dev/null 2>&1; then
        userdel "${SERVICE_USER}" 2>/dev/null || true
    fi
    echo "[OK] Removed /opt/slyber_sfu (config & telemetry) and system user ${SERVICE_USER}."
else
    echo "[OK] Binary and systemd service removed. Config and telemetry preserved in /opt/slyber_sfu (set PURGE_DATA=true to delete)."
fi