#!/usr/bin/env bash
# ================================================================
# uninstall.sh
# Removes all WinPC Control components from this Ubuntu PC.
# Run with sudo:  sudo bash uninstall.sh
#
# Removes: systemd user service, UFW rule, sudoers drop-in,
#          and /opt/qsys-winpc-control/
#
# Version: 0.1.0-alpha
# ================================================================

set -euo pipefail

WORK_DIR="/opt/qsys-winpc-control"
CONFIG_FILE="$WORK_DIR/config.txt"
SERVICE_NAME="winpc-control"
SUDOERS_FILE="/etc/sudoers.d/winpc-control"

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

# Read port from config if present
PORT=2207
if [[ -f "$CONFIG_FILE" ]]; then
    PORT_LINE=$(grep -E "^PORT=[0-9]+$" "$CONFIG_FILE" | head -1 || true)
    if [[ -n "$PORT_LINE" ]]; then
        PORT="${PORT_LINE#PORT=}"
    fi
fi

echo ""
echo "================================================"
echo "  WinPC Control - Uninstall"
echo "================================================"
echo "  Port: $PORT"
echo ""


# ---- Stop and remove systemd user service ----
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
step "Removing UFW firewall rule (TCP port $PORT)"
if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
    ok "UFW rule removed"
else
    echo "     [WARN] ufw not found — manually remove TCP port $PORT rule from your firewall"
fi


# ---- Remove sudoers drop-in ----
step "Removing sudoers rule"
if [[ -f "$SUDOERS_FILE" ]]; then
    rm -f "$SUDOERS_FILE"
    ok "Sudoers rule removed"
else
    ok "No sudoers rule found — nothing to remove"
fi


# ---- Remove work directory ----
step "Removing $WORK_DIR"
if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    ok "$WORK_DIR removed"
else
    ok "$WORK_DIR not found — nothing to remove"
fi


echo ""
echo "================================================"
echo "  Uninstall complete."
echo "================================================"
echo ""
