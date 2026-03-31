#!/usr/bin/env bash
# ================================================================
# uninstall.sh
# Removes all Remote PC Control components from this Ubuntu PC.
# Run with sudo:  sudo bash uninstall.sh
#
# Removes: systemd user service, UFW rule, sudoers drop-in,
#          and /opt/qsys-remotepc-control/
#
# Version: 0.1.0-alpha
# ================================================================

set -euo pipefail

WORK_DIR="/opt/qsys-remotepc-control"
CONFIG_FILE="$WORK_DIR/config.txt"
SERVICE_NAME="remotepc-control"
SUDOERS_FILE="/etc/sudoers.d/remotepc-control"

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run with sudo."
    echo "Usage: sudo bash uninstall.sh"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
REAL_UID=$(id -u "$REAL_USER")

step()  { echo -e "\n  >> $1"; }
ok()    { echo "     OK: $1"; }

# Figure out which port was used so we can remove the right firewall rule
PORT=2207
if [[ -f "$CONFIG_FILE" ]]; then
    PORT_LINE=$(grep -E "^PORT=[0-9]+$" "$CONFIG_FILE" | head -1 || true)
    if [[ -n "$PORT_LINE" ]]; then
        PORT="${PORT_LINE#PORT=}"
    fi
fi

echo ""
echo "================================================"
echo "  Remote PC Control - Uninstall"
echo "================================================"
echo "  Port: $PORT"
echo ""


# ---- Stop and remove systemd user service ----
# We stop first, then disable, then delete the unit file and reload.
# XDG_RUNTIME_DIR is needed for the same reason as in install.sh -
# running systemctl --user through sudo without it can't find the bus.
step "Removing systemd user service '$SERVICE_NAME'"
if sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    systemctl --user is-active "$SERVICE_NAME.service" >/dev/null 2>&1; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
        systemctl --user stop "$SERVICE_NAME.service" 2>/dev/null || true
fi
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    systemctl --user disable "$SERVICE_NAME.service" 2>/dev/null || true
rm -f "$REAL_HOME/.config/systemd/user/$SERVICE_NAME.service"
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    systemctl --user daemon-reload 2>/dev/null || true
ok "Service removed"


# ---- Remove UFW firewall rule ----
# We delete the rule by port number. If the port was changed after install
# and the config is already gone, we'll try the default 2207.
step "Removing UFW firewall rule (TCP port $PORT)"
if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
    ok "UFW rule removed"
else
    echo "     [WARN] ufw not found - manually remove TCP port $PORT rule from your firewall"
fi


# ---- Remove sudoers drop-in ----
# This was the NOPASSWD rule that allowed `sudo shutdown` without a prompt.
step "Removing sudoers rule"
if [[ -f "$SUDOERS_FILE" ]]; then
    rm -f "$SUDOERS_FILE"
    ok "Sudoers rule removed"
else
    ok "No sudoers rule found - nothing to remove"
fi


# ---- Remove work directory ----
# This deletes the server script, config (including the auth token),
# and log file. If you need to keep the token, back it up first.
step "Removing $WORK_DIR"
if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    ok "$WORK_DIR removed"
else
    ok "$WORK_DIR not found - nothing to remove"
fi


echo ""
echo "================================================"
echo "  Uninstall complete."
echo "================================================"
echo ""
