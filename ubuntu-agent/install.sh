#!/usr/bin/env bash
# ============================================================
# install.sh
# One-time setup for Remote PC Control on Ubuntu 24.04 LTS.
# Run with sudo:  sudo bash install.sh
#
# Creates:
#   /opt/qsys-remotepc-control/           Working directory
#   /opt/qsys-remotepc-control/config.txt Config (PORT=, TOKEN=)
#   ~/.config/systemd/user/remotepc-control.service  Systemd user service
#   /etc/sudoers.d/remotepc-control       Passwordless shutdown
#   UFW rule for the configured port
#
# Version: 0.1.0-alpha
# ============================================================

set -euo pipefail

# Port and token can be passed as positional args:
#   sudo bash install.sh 8080 "my-custom-token"
# Both are optional - defaults to port 2207 and auto-generated token.
PORT="${1:-2207}"
TOKEN="${2:-}"

WORK_DIR="/opt/qsys-remotepc-control"
SERVER_SCRIPT="remotepc-control-server.py"
CONFIG_FILE="$WORK_DIR/config.txt"
LOG_FILE="$WORK_DIR/install.log"
SERVICE_NAME="remotepc-control"
SUDOERS_FILE="/etc/sudoers.d/remotepc-control"

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run with sudo."
    echo "Usage: sudo bash install.sh [port] [token]"
    exit 1
fi

# Figure out who actually ran sudo - we need their home dir
# and UID to set up the systemd user service correctly.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
REAL_UID=$(id -u "$REAL_USER")

if [[ "$REAL_USER" == "root" ]]; then
    echo "ERROR: Do not run as root directly. Use 'sudo bash install.sh' from a normal user account."
    exit 1
fi

# The script dir is where install.sh lives - the server script
# should be sitting right next to it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step()  { echo -e "\n  >> $1"; }
ok()    { echo "     OK: $1"; }
fail()  { echo "     FAIL: $1"; exit 1; }

echo ""
echo "================================================"
echo "  Remote PC Control - Ubuntu Setup"
echo "================================================"
echo "  Port:  $PORT"
echo "  User:  $REAL_USER"
echo ""


# ---- Step 1: Install dependencies ----
step "Checking dependencies"
# python3 is usually already present on Ubuntu 24.04 but we check anyway.
# pulseaudio-utils gives us the pactl command for volume/mute control.
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
    # 32 random bytes -> base64 gives a 44-char string.
    # Same approach the Windows installer uses (RNGCryptoServiceProvider).
    TOKEN=$(python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())")
fi

cat > "$CONFIG_FILE" <<EOF
PORT=$PORT
TOKEN=$TOKEN
EOF
chown "$REAL_USER:$REAL_USER" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"    # only the owning user should read the token
ok "Token saved to $CONFIG_FILE"


# ---- Step 5: Configure passwordless shutdown via sudoers ----
# The server script calls `sudo shutdown now` when it gets a SHUTDOWN
# command from Q-SYS. Without this sudoers entry, it would hang waiting
# for a password prompt in a headless session.
step "Configuring passwordless shutdown for $REAL_USER"
cat > "$SUDOERS_FILE" <<EOF
# Allow Remote PC Control server to shut down without a password
$REAL_USER ALL=(ALL) NOPASSWD: /sbin/shutdown
EOF
chmod 440 "$SUDOERS_FILE"
# Always validate sudoers syntax - a broken file here can lock you
# out of sudo entirely, which would be very bad.
if visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    ok "Sudoers rule created at $SUDOERS_FILE"
else
    rm -f "$SUDOERS_FILE"
    fail "Sudoers syntax check failed - file removed"
fi


# ---- Step 6: Add UFW firewall rule ----
# Most Ubuntu desktop installs have UFW active by default.
# If it's not installed we just warn - the admin knows their firewall.
step "Adding UFW firewall rule (TCP port $PORT)"
if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT/tcp" comment "Remote PC Control HTTP" >/dev/null 2>&1 || true
    ok "UFW rule added (TCP $PORT inbound)"
else
    echo "     [WARN] ufw not found - manually open TCP port $PORT in your firewall"
fi


# ---- Step 7: Create systemd user service ----
# This runs as a user-level service (not system) because the audio subsystem
# (PipeWire/PulseAudio) is only accessible from the user's own session.
# Running as a system service would mean pactl can't find any sinks.
step "Creating systemd user service"
SERVICE_DIR="$REAL_HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config"

# DISPLAY=:0 is set so the service has access to X11/Wayland if needed.
# sound.target ensures PipeWire is up before we try to use pactl.
cat > "$SERVICE_DIR/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Remote PC Control Server for Q-SYS
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

# enable-linger lets user services run even when nobody is logged in.
# Without it the service would stop when the user's last session closes.
loginctl enable-linger "$REAL_USER" 2>/dev/null || true

# XDG_RUNTIME_DIR must be set explicitly when running systemctl --user
# from a sudo context, otherwise systemd can't find the user's bus.
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
echo "  Remote PC Control - Installation complete!"
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
