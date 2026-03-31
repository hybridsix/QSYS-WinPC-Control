#!/usr/bin/env python3
# ================================================================
# remotepc-control-server.py
# Persistent HTTP control server for Q-SYS Remote PC Control plugin.
#
# Runs as a systemd user service in the interactive session
# (required for PulseAudio/PipeWire audio access via pactl).
#
# Endpoints (all require Authorization: Bearer <token>):
#   GET  /status    Returns current volume, mute state, timestamp
#   POST /command   Accepts VOLUME:N  MUTE:0  MUTE:1  SHUTDOWN
#   GET  /command?cmd=...  (Q-SYS emulate mode fallback)
#
# Config: /opt/qsys-remotepc-control/config.txt  (PORT=, TOKEN=)
# Log:    /opt/qsys-remotepc-control/server.log
#
# Version: 0.1.0-alpha
# ================================================================

import os
import sys
import subprocess
import socket
import re
import signal
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from threading import Timer           # used to delay shutdown so the HTTP response goes out first

# ============================================
# CONFIGURATION
# ============================================

# Paths here must match what install.sh creates
WORK_DIR    = "/opt/qsys-remotepc-control"
CONFIG_FILE = os.path.join(WORK_DIR, "config.txt")
LOG_FILE    = os.path.join(WORK_DIR, "server.log")
LOG_MAX_LINES = 500    # keep the log file from growing unbounded

_log_write_count = 0   # running counter - triggers trim every 100 writes


def read_config():
    """Load PORT and TOKEN from config.txt (KEY=VALUE format, one per line).
    Falls back to defaults if the file is missing or a key isn't present."""
    cfg = {"PORT": "2207", "TOKEN": ""}
    if os.path.isfile(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            for line in f:
                line = line.strip()
                m = re.match(r"^(\w+)=(.+)$", line)
                if m:
                    cfg[m.group(1)] = m.group(2).strip()
    return cfg


config = read_config()
PORT   = int(config["PORT"])
TOKEN  = config["TOKEN"]

if not TOKEN:
    print(f"ERROR: No auth token found in {CONFIG_FILE}. Run install.sh first.")
    sys.exit(1)


# ============================================
# LOGGING
# ============================================

def write_log(message):
    """Append a timestamped line to server.log. We don't use Python's logging
    module - overkill for a single-file log that just needs timestamps."""
    global _log_write_count
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{ts}] {message}\n")
    except OSError:
        pass  # not much we can do if the log itself is broken
    _log_write_count += 1
    if _log_write_count % 100 == 0:
        trim_log()


def trim_log():
    """Chop the log to the most recent LOG_MAX_LINES entries.
    Called once at startup and periodically after that to prevent
    the file from growing forever on a PC that runs for months."""
    if not os.path.isfile(LOG_FILE):
        return
    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        if len(lines) > LOG_MAX_LINES:
            with open(LOG_FILE, "w") as f:
                f.writelines(lines[-LOG_MAX_LINES:])
    except OSError:
        pass


# ============================================
# AUDIO CONTROL  (pactl - PulseAudio / PipeWire)
# ============================================
# All volume/mute control goes through pactl, which talks to whatever audio
# server the desktop session is running (PipeWire on Ubuntu 24.04, or classic
# PulseAudio on older installs). The pactl CLI comes from pulseaudio-utils.
#
# Important: pactl needs to connect to the user's audio daemon, which is why
# the systemd service runs as a --user unit (not system-level). Running this
# as root or a different user means pactl won't find any sinks.

def _run_pactl(args):
    """Run a pactl command and return its stdout.
    Raises RuntimeError on non-zero exit. 5s timeout is generous -
    pactl usually returns in well under 50ms."""
    result = subprocess.run(
        ["pactl"] + args,
        capture_output=True, text=True, timeout=5
    )
    if result.returncode != 0:
        raise RuntimeError(f"pactl {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def get_volume():
    """Return master volume as integer 0-100, or -1 on error."""
    try:
        out = _run_pactl(["get-sink-volume", "@DEFAULT_SINK@"])
        # pactl output looks something like:
        #   Volume: front-left: 42000 /  64% / -11.78 dB,   front-right: ...
        # We just grab the first percentage - good enough for master vol.
        m = re.search(r"(\d+)%", out)
        if m:
            return int(m.group(1))
        return -1
    except Exception as e:
        write_log(f"ERROR reading volume: {e}")
        return -1


def set_volume(percent):
    """Set master volume to percent (0-100). Returns a diagnostic string
    for logging, e.g. 'set 45%->70%' or 'already 70%'."""
    percent = max(0, min(100, percent))
    try:
        before = get_volume()
        if before == percent:
            return f"already {percent}%"
        # @DEFAULT_SINK@ targets whatever output the desktop session considers
        # primary - no need to enumerate sinks ourselves
        _run_pactl(["set-sink-volume", "@DEFAULT_SINK@", f"{percent}%"])
        after = get_volume()
        write_log(f"Volume set to {percent}% (readBack={after}%)")
        return f"set {before}%->{after}%"
    except Exception as e:
        write_log(f"ERROR setting volume: {e}")
        raise


def get_mute():
    """Check whether the default sink is muted."""
    try:
        out = _run_pactl(["get-sink-mute", "@DEFAULT_SINK@"])
        return "yes" in out.lower()   # output is literally "Mute: yes" or "Mute: no"
    except Exception as e:
        write_log(f"ERROR reading mute: {e}")
        return False


def set_mute(muted):
    """Mute or unmute the default sink. pactl takes 1/0 for mute/unmute."""
    try:
        val = "1" if muted else "0"
        _run_pactl(["set-sink-mute", "@DEFAULT_SINK@", val])
        write_log(f"Mute set to {muted}")
    except Exception as e:
        write_log(f"ERROR setting mute: {e}")
        raise


# ============================================
# SYSTEM INFO
# ============================================

def get_mac_address():
    """Get the MAC address of whichever NIC handles the default route.
    The Q-SYS plugin caches this for Wake-on-LAN - it needs the MAC
    even when the PC is powered off, so it grabs it during status polls."""
    try:
        # `ip route show default` gives us the outbound interface name.
        # Typical output: "default via 192.168.1.1 dev eth0 proto dhcp ..."
        result = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True, text=True, timeout=5
        )
        m = re.search(r"dev\s+(\S+)", result.stdout)
        if not m:
            return ""
        iface = m.group(1)

        # Pull the hardware address from that interface
        # `ip link show eth0` includes: "link/ether aa:bb:cc:dd:ee:ff brd ..."
        result = subprocess.run(
            ["ip", "link", "show", iface],
            capture_output=True, text=True, timeout=5
        )
        m = re.search(r"link/ether\s+([\da-fA-F:]+)", result.stdout)
        if m:
            return m.group(1).upper()
        return ""
    except Exception:
        return ""


def get_hostname():
    return socket.gethostname()


def get_status_body():
    """Build the status response body. The Q-SYS plugin parses these key:value
    lines - the order doesn't matter but the keys must match exactly."""
    vol      = get_volume()
    muted    = get_mute()
    mute_int = "1" if muted else "0"
    ts       = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    mac      = get_mac_address()
    hostname = get_hostname()
    # CRLF line endings match the Windows agent (the Lua parser handles both)
    return f"VOLUME:{vol}\r\nMUTE:{mute_int}\r\nMAC:{mac}\r\nHOSTNAME:{hostname}\r\nUPDATED:{ts}\r\n"


# ============================================
# COMMAND ROUTER
# ============================================

def invoke_command(raw_message):
    """Parse and execute a command from the Q-SYS plugin.
    Format is always COMMAND:VALUE, e.g. VOLUME:65, MUTE:1, SHUTDOWN."""
    write_log(f"CMD: {raw_message}")

    parts   = raw_message.split(":", 1)
    command = parts[0].upper().strip()
    value   = parts[1].strip() if len(parts) > 1 else ""

    if command == "VOLUME":
        try:
            pct = int(value)
            pct = max(0, min(100, pct))   # clamp just in case
            set_volume(pct)
        except ValueError:
            write_log(f"ERROR: bad volume value '{value}'")

    elif command == "MUTE":
        if value == "1":
            set_mute(True)
        elif value == "0":
            set_mute(False)
        else:
            write_log(f"ERROR: bad mute value '{value}'")

    elif command == "SHUTDOWN":
        write_log("Shutdown command received - initiating")
        # Fire the actual shutdown on a 1-second timer so the HTTP 200
        # response has time to get back to Q-SYS before we go down
        Timer(1.0, _do_shutdown).start()

    else:
        write_log(f"WARNING: unknown command '{command}'")


def _do_shutdown():
    """Called from a Timer thread after the HTTP response is sent.
    Needs sudo - the sudoers drop-in from install.sh grants
    NOPASSWD for /sbin/shutdown so this works without prompting."""
    subprocess.run(["sudo", "shutdown", "now"], timeout=10)


# ============================================
# HTTP REQUEST HANDLER
# ============================================

class QSYSHandler(BaseHTTPRequestHandler):
    """HTTP request handler for Q-SYS plugin communication.

    Two endpoints:
      /status  - GET, returns volume/mute/mac/hostname
      /command - POST (or GET with ?cmd= for Q-SYS Designer emulate mode)

    Every request must carry the Bearer token or it gets a 401."""

    # Kill the default BaseHTTPRequestHandler stderr logging -
    # we write everything to server.log ourselves
    def log_message(self, format, *args):
        pass

    def _check_auth(self):
        """Validate the Bearer token. Returns False (and sends 401) on mismatch."""
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {TOKEN}":
            write_log(f"AUTH FAIL from {self.client_address[0]}:{self.client_address[1]}")
            self._send(401, "Unauthorized")
            return False
        return True

    def _send(self, code, body="", content_type="text/plain; charset=utf-8"):
        """Send a complete HTTP response. Handles encoding and Content-Length."""
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        encoded = body.encode("utf-8") if body else b""
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        if encoded:
            self.wfile.write(encoded)

    def do_GET(self):
        parsed = urlparse(self.path)
        path   = parsed.path.rstrip("/").lower()

        write_log(f"GET {path} from {self.client_address[0]}:{self.client_address[1]}")

        if not self._check_auth():
            return

        if path == "/status":
            # Normal poll - the plugin hits this every few seconds
            body = get_status_body()
            self._send(200, body)

        elif path == "/command":
            # Q-SYS Designer's emulate mode downgrades POST to GET and drops
            # the body entirely, so commands arrive as ?cmd= query params.
            # On real Core hardware POST works fine (handled in do_POST).
            qs = parse_qs(parsed.query)
            cmd = qs.get("cmd", [""])[0].strip()
            if cmd:
                self._send(200, "OK")
                invoke_command(cmd)
            else:
                self._send(400, "Empty command")

        else:
            self._send(404, "Not found")

    def do_POST(self):
        parsed = urlparse(self.path)
        path   = parsed.path.rstrip("/").lower()

        write_log(f"POST {path} from {self.client_address[0]}:{self.client_address[1]}")

        if not self._check_auth():
            return

        if path == "/command":
            # Read the POST body - command string like "VOLUME:65"
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8").strip() if content_length > 0 else ""

            # If the body is empty, check query string as a fallback
            # (covers the GET-downgrade edge case from emulate mode)
            if not body:
                qs = parse_qs(parsed.query)
                body = qs.get("cmd", [""])[0].strip()

            if body:
                # Respond 200 before executing - critical for SHUTDOWN,
                # otherwise the response never makes it back to Q-SYS
                self._send(200, "OK")
                invoke_command(body)
            else:
                self._send(400, "Empty command")

        else:
            self._send(404, "Not found")


# ============================================
# MAIN
# ============================================

def main():
    # PipeWire (or PulseAudio) may not be fully initialized yet when the
    # systemd user service kicks off at boot - especially on slower hardware.
    # We retry for up to 30 seconds before giving up.
    audio_ready = False
    for attempt in range(15):
        try:
            get_volume()
            audio_ready = True
            break
        except Exception:
            import time
            time.sleep(2)

    if not audio_ready:
        write_log("WARNING: Audio subsystem not ready after 30 seconds - volume/mute may not work")

    trim_log()    # housekeeping from previous runs

    # Bind on all interfaces so the Q-SYS Core can reach us regardless
    # of which NIC or VLAN it's coming from
    server = HTTPServer(("0.0.0.0", PORT), QSYSHandler)
    write_log(f"=== RemotePCControlServer (Linux) started on port {PORT} ===")
    print(f"Remote PC Control Server listening on port {PORT}")

    # systemd sends SIGTERM on `systemctl --user stop`, SIGINT covers Ctrl+C
    # during manual testing from a terminal
    def handle_signal(signum, frame):
        write_log("=== RemotePCControlServer stopped (signal) ===")
        server.shutdown()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        write_log("=== RemotePCControlServer stopped ===")


if __name__ == "__main__":
    main()
