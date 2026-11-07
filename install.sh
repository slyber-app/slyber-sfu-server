#!/usr/bin/env bash
set -euo pipefail

REPO="slyber-app/slyber-sfu-server"
INSTALL_DIR="/opt/slyber_sfu"
BIN_PATH="${INSTALL_DIR}/slyber_sfu"
SYMLINK_PATH="/usr/local/bin/slyber_sfu"
SERVICE_FILE="/etc/systemd/system/slyber_sfu.service"
SERVICE_USER="slyber_sfu"
VERSION="${VERSION:-latest}"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERR] This script must be run as root (use sudo)." >&2
    exit 1
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [ "${OS}" != "linux" ]; then
    echo "[ERR] Unsupported operating system: ${OS} (Linux is required)." >&2
    exit 1
fi

RAW_ARCH="$(uname -m)"
case "${RAW_ARCH}" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "[ERR] Unsupported CPU architecture: ${RAW_ARCH}" >&2
        exit 1
        ;;
esac

BIN_FILENAME="slyber_sfu-linux-${ARCH}"
echo "[INFO] Detected platform: linux/${ARCH}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [ "${VERSION}" = "latest" ]; then
    RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
else
    RELEASE_BASE="https://github.com/${REPO}/releases/download/${VERSION}"
fi
RAW_FALLBACK_BASE="https://raw.githubusercontent.com/${REPO}/main/bin"

echo "[INFO] Downloading ${BIN_FILENAME}..."
if curl -fsSL "${RELEASE_BASE}/${BIN_FILENAME}" -o "${TMP_DIR}/${BIN_FILENAME}" 2>/dev/null; then
    DOWNLOAD_SOURCE="${RELEASE_BASE}"
elif curl -fsSL "${RAW_FALLBACK_BASE}/${BIN_FILENAME}" -o "${TMP_DIR}/${BIN_FILENAME}" 2>/dev/null; then
    DOWNLOAD_SOURCE="${RAW_FALLBACK_BASE}"
else
    echo "[ERR] Failed to download ${BIN_FILENAME} from ${REPO}." >&2
    exit 1
fi

if curl -fsSL "${DOWNLOAD_SOURCE}/SHA256SUMS" -o "${TMP_DIR}/SHA256SUMS" 2>/dev/null; then
    echo "[INFO] Verifying SHA256 checksum..."
    (
        cd "${TMP_DIR}"
        grep " ${BIN_FILENAME}\$" SHA256SUMS | sha256sum -c - >/dev/null
    )
    echo "[OK] Checksum verified"
fi

timedatectl set-ntp true 2>/dev/null || true

sysctl -w net.core.rmem_max=8388608 >/dev/null 2>&1 || true
sysctl -w net.core.wmem_max=8388608 >/dev/null 2>&1 || true
printf "net.core.rmem_max=8388608\nnet.core.wmem_max=8388608\n" > /etc/sysctl.d/99-slyber-sfu.conf 2>/dev/null || true

if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
    NOLOGIN_SHELL="/usr/sbin/nologin"
    if [ ! -x "${NOLOGIN_SHELL}" ] && [ -x "/sbin/nologin" ]; then
        NOLOGIN_SHELL="/sbin/nologin"
    elif [ ! -x "${NOLOGIN_SHELL}" ]; then
        NOLOGIN_SHELL="/bin/false"
    fi
    useradd --system --no-create-home --home-dir "${INSTALL_DIR}" --shell "${NOLOGIN_SHELL}" "${SERVICE_USER}"
    echo "[OK] Created dedicated system user: ${SERVICE_USER}"
fi

mkdir -p "${INSTALL_DIR}/certs"
chmod 750 "${INSTALL_DIR}"

install -m 0755 "${TMP_DIR}/${BIN_FILENAME}" "${BIN_PATH}"
ln -sf "${BIN_PATH}" "${SYMLINK_PATH}"
echo "[OK] Installed binary to ${BIN_PATH} (symlinked to ${SYMLINK_PATH})"

if [ ! -f "${INSTALL_DIR}/.env" ]; then
    DETECTED_IP="$(curl -4fsSL --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"
    GENERATED_TURN_SECRET="${TURN_SECRET:-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)}"
    GENERATED_JWT_SECRET="${JWT_SECRET:-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)}"
    GENERATED_NODE_SECRET="${NODE_SECRET:-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)}"

    CONF_NODE_ID="${SFU_NODE_ID:-slyber-sfu-01}"
    CONF_PUBLIC_IP="${PUBLIC_IP:-${DETECTED_IP}}"
    CONF_REALM="${REALM:-slyber.local}"
    CONF_UDP_PORT="${SFU_UDP_PORT:-443}"
    CONF_TCP_PORT="${SFU_TCP_PORT:-443}"
    CONF_HTTP_PORT="${SFU_HTTP_PORT:-8090}"
    CONF_WORKERS="${SO_REUSEPORT_WORKERS:-4}"
    CONF_AUTH_MODE="${AUTH_MODE:-secret}"
    CONF_REDIS_ADDR="${REDIS_ADDR:-127.0.0.1:6379}"
    CONF_REDIS_USERNAME="${REDIS_USERNAME:-}"
    CONF_REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    CONF_REDIS_DB="${REDIS_DB:-0}"

    cat > "${INSTALL_DIR}/.env" <<EOF
SFU_NODE_ID="${CONF_NODE_ID}"
PUBLIC_IP="${CONF_PUBLIC_IP}"
REALM="${CONF_REALM}"
SFU_UDP_PORT=${CONF_UDP_PORT}
SFU_TCP_PORT=${CONF_TCP_PORT}
SFU_HTTP_PORT=${CONF_HTTP_PORT}
SO_REUSEPORT_WORKERS=${CONF_WORKERS}
ENABLE_ICE_TCP=true
ENABLE_QUIC=true
TURN_MODE="both"
AUTH_MODE="${CONF_AUTH_MODE}"
TURN_SECRET="${GENERATED_TURN_SECRET}"
JWT_SECRET="${GENERATED_JWT_SECRET}"
NODE_SECRET="${GENERATED_NODE_SECRET}"
CREDENTIAL_TTL_SEC=3600
REQUIRE_SRTP=false
REQUIRE_E2EE=false
REDIS_ADDR="${CONF_REDIS_ADDR}"
REDIS_USERNAME="${CONF_REDIS_USERNAME}"
REDIS_PASSWORD="${CONF_REDIS_PASSWORD}"
REDIS_DB=${CONF_REDIS_DB}
MAX_KBPS_PER_TRACK=3500
MAX_KBPS_PER_SESSION=10000
DEFAULT_ROOM_PROFILE="conference"
ENABLE_SIMULCAST=true
ENABLE_SVC=true
ENABLE_WHIP_WHEP=true
ENABLE_MOQ_RELAY=true
ENABLE_AI_GATEWAY=true
ENABLE_CASCADE_PIPE=true
ENABLE_INSPECTOR=true
EOF
    chmod 600 "${INSTALL_DIR}/.env"
    echo "[OK] Created initial configuration in ${INSTALL_DIR}/.env"
else
    echo "[INFO] Existing configuration found at ${INSTALL_DIR}/.env (preserved)"
fi

chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "[INFO] Applying UFW firewall rules..."
    ufw allow 443/udp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    ufw allow 8090/tcp >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    echo "[INFO] Applying firewalld rules..."
    firewall-cmd --permanent --add-port=443/udp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=443/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=8090/tcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Slyber SFU Server (Single-Port WebRTC SFU, TURN, WHIP/WHEP & MoQ)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${BIN_PATH} server
Restart=always
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SERVICE_FILE}"
systemctl daemon-reload
systemctl enable slyber_sfu >/dev/null 2>&1
systemctl restart slyber_sfu
sleep 1

echo "[INFO] Running self-diagnostics..."
(cd "${INSTALL_DIR}" && set -a && . "${INSTALL_DIR}/.env" && set +a && "${BIN_PATH}" doctor) || true

CURRENT_TURN_SECRET="$(grep '^TURN_SECRET=' "${INSTALL_DIR}/.env" | cut -d= -f2- | tr -d '"')"
CURRENT_NODE_SECRET="$(grep '^NODE_SECRET=' "${INSTALL_DIR}/.env" | cut -d= -f2- | tr -d '"')"
echo ""
echo "[OK] Slyber SFU Server is installed and running."
echo "  Service     : systemctl status slyber_sfu (user: ${SERVICE_USER})"
echo "  Config file : ${INSTALL_DIR}/.env"
echo "  TURN Secret : ${CURRENT_TURN_SECRET}"
echo "  Node Secret : ${CURRENT_NODE_SECRET}"
echo "  Diagnostics : sudo slyber_sfu doctor"