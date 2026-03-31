#!/usr/bin/env bash
# ============================================================
# install.sh
# One-time setup for WinPC Control on Ubuntu 24.04 LTS.
# Run with sudo:  sudo bash install.sh
#
# Creates:
#   /opt/qsys-winpc-control/           Working directory
#   /opt/qsys-winpc-control/config.txt Config (PORT=, TOKEN=)
#   ~/.config/systemd/user/winpc-control.service  Systemd user service
#   /etc/sudoers.d/winpc-control       Passwordless shutdown
#   UFW rule for the configured port
#
# Version: 0.1.0-alpha
# ============================================================

set -euo pipefail

PORT="${1:-2207}"
TOKEN="${2:-}"

WORK_DIR="/opt/qsys-winpc-control"
SERVER_SCRIPT="winpc-control-server.py"
CONFIG_FILE="$WORK_DIR/config.txt"
LOG_FILE="$WORK_DIR/install.log"
SERVICE_NAME="winpc-control"
SUDOERS_FILE="/etc/sudoers.d/winpc-control"

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run with sudo."
    echo "Usage: sudo bash install.sh [port] [token]"
    exit 1
fi

# Detect the real user (not root) who invoked sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
REAL_UID=$(id -u "$REAL_USER")

if [[ "$REAL_USER" == "root" ]]; then
    echo "ERROR: Do not run as root directly. Use 'sudo bash install.sh' from a normal user account."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step()  { echo -e "\n  >> $1"; }
ok()    { echo "     OK: $1"; }
fail()  { echo "     FAIL: $1"; exit 1; }

echo ""
echo "================================================"
echo "  WinPC Control - Ubuntu Setup"
echo "================================================"
echo "  Port:  $PORT"
echo "  User:  $REAL_USER"
echo ""


# ---- Step 1: Install dependencies ----
step "Checking dependencies"
DEPS_NEEDED=""
command -v python3 >/dev/null 2>&1 || DEPS_NEEDED="$DEPS_NEEDED python3"
command -v pactl   >/dev/null 2>&1 || DEPS_NEEDED="$DEPS_NEEDED pulseaudio-utils"

if [[ -n "$DEPS_NEEDED" ]]; then
    echo "     Installing:$DEPS_NEEDED"
    apt-get update -qq
    apt-get install -y -qq $DEPS_NEEDED
fi
ok "python3 and pactl available"


# ---- Step 2: Create working directory ----
step "Creating working directory $WORK_DIR"
mkdir -p "$WORK_DIR"
chown "$REAL_USER:$REAL_USER" "$WORK_DIR"
ok "$WORK_DIR ready"


# ---- Step 3: Copy server script and uninstall script ----
step "Copying server script"
SOURCE="$SCRIPT_DIR/$SERVER_SCRIPT"
if [[ ! -f "$SOURCE" ]]; then
    fail "$SERVER_SCRIPT not found next to install.sh. Make sure both files are in the same folder."
fi
cp "$SOURCE" "$WORK_DIR/$SERVER_SCRIPT"
chmod +x "$WORK_DIR/$SERVER_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$WORK_DIR/$SERVER_SCRIPT"
ok "Copied $SERVER_SCRIPT to $WORK_DIR"

UNINSTALL_SOURCE="$SCRIPT_DIR/uninstall.sh"
if [[ -f "$UNINSTALL_SOURCE" ]]; then
    cp "$UNINSTALL_SOURCE" "$WORK_DIR/uninstall.sh"
    chmod +x "$WORK_DIR/uninstall.sh"
    chown "$REAL_USER:$REAL_USER" "$WORK_DIR/uninstall.sh"
    ok "Copied uninstall.sh to $WORK_DIR"
else
    echo "     [WARN] uninstall.sh not found next to install.sh -- skipping"
fi


# ---- Step 4: Generate auth token and write config ----
step "Generating auth token"
if [[ -n "$TOKEN" ]]; then
    echo "     Using supplied token."
else
    TOKEN=$(python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())")
fi

cat > "$CONFIG_FILE" <<EOF
PORT=$PORT
TOKEN=$TOKEN
EOF
chown "$REAL_USER:$REAL_USER" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
ok "Token saved to $CONFIG_FILE"


# ---- Step 5: Configure passwordless shutdown via sudoers ----
step "Configuring passwordless shutdown for $REAL_USER"
cat > "$SUDOERS_FILE" <<EOF
# Allow WinPC Control server to shut down without a password
$REAL_USER ALL=(ALL) NOPASSWD: /sbin/shutdown
EOF
chmod 440 "$SUDOERS_FILE"
# Validate the sudoers file
if visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    ok "Sudoers rule created at $SUDOERS_FILE"
else
    rm -f "$SUDOERS_FILE"
    fail "Sudoers syntax check failed — file removed"
fi


# ---- Step 6: Add UFW firewall rule ----
step "Adding UFW firewall rule (TCP port $PORT)"
if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT/tcp" comment "WinPC Control HTTP" >/dev/null 2>&1 || true
    ok "UFW rule added (TCP $PORT inbound)"
else
    echo "     [WARN] ufw not found — manually open TCP port $PORT in your firewall"
fi


# ---- Step 7: Create systemd user service ----
step "Creating systemd user service"
SERVICE_DIR="$REAL_HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config"

cat > "$SERVICE_DIR/$SERVICE_NAME.service" <<EOF
[Unit]
Description=WinPC Control Server for Q-SYS
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $WORK_DIR/$SERVER_SCRIPT
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF
chown "$REAL_USER:$REAL_USER" "$SERVICE_DIR/$SERVICE_NAME.service"

# Enable and start the service as the real user
# loginctl enable-linger allows user services to run without an active login session
loginctl enable-linger "$REAL_USER" 2>/dev/null || true

sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    systemctl --user daemon-reload

sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    systemctl --user enable "$SERVICE_NAME.service"

sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    systemctl --user restart "$SERVICE_NAME.service"

ok "Systemd user service '$SERVICE_NAME' enabled and started"


# ---- Step 8: Log install and display token ----
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$TIMESTAMP] Installed by $REAL_USER on $(hostname) (port $PORT)" >> "$LOG_FILE"
chown "$REAL_USER:$REAL_USER" "$LOG_FILE"

echo ""
echo "================================================"
echo "  WinPC Control - Installation complete!"
echo "================================================"
echo ""
echo "  Copy this token into the Q-SYS plugin properties:"
echo ""
echo "  $TOKEN"
echo ""
echo "  The server is running now and will auto-start on boot."
echo ""
echo "  Useful commands:"
echo "    Status:  systemctl --user status $SERVICE_NAME"
echo "    Logs:    journalctl --user -u $SERVICE_NAME -f"
echo "    Restart: systemctl --user restart $SERVICE_NAME"
echo ""
