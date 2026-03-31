#!/usr/bin/env python3
# ================================================================
# winpc-control-server.py
# Persistent HTTP control server for Q-SYS WinPC Control plugin.
#
# Runs as a systemd user service in the interactive session
# (required for PulseAudio/PipeWire audio access via pactl).
#
# Endpoints (all require Authorization: Bearer <token>):
#   GET  /status    Returns current volume, mute state, timestamp
#   POST /command   Accepts VOLUME:N  MUTE:0  MUTE:1  SHUTDOWN
#   GET  /command?cmd=...  (Q-SYS emulate mode fallback)
#
# Config: /opt/qsys-winpc-control/config.txt  (PORT=, TOKEN=)
# Log:    /opt/qsys-winpc-control/server.log
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
from threading import Timer

# ============================================
# CONFIGURATION
# ============================================

WORK_DIR    = "/opt/qsys-winpc-control"
CONFIG_FILE = os.path.join(WORK_DIR, "config.txt")
LOG_FILE    = os.path.join(WORK_DIR, "server.log")
LOG_MAX_LINES = 500

_log_write_count = 0


def read_config():
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
    global _log_write_count
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{ts}] {message}\n")
    except OSError:
        pass
    _log_write_count += 1
    if _log_write_count % 100 == 0:
        trim_log()


def trim_log():
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
# AUDIO CONTROL  (pactl — PulseAudio / PipeWire)
# ============================================

def _run_pactl(args):
    """Run a pactl command, returning stdout. Raises on failure."""
    result = subprocess.run(
        ["pactl"] + args,
        capture_output=True, text=True, timeout=5
    )
    if result.returncode != 0:
        raise RuntimeError(f"pactl {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def get_volume():
    """Return master volume as integer 0-100."""
    try:
        out = _run_pactl(["get-sink-volume", "@DEFAULT_SINK@"])
        # Output like: "Volume: front-left: 42000 /  64% / -11.78 dB,   front-left: ..."
        m = re.search(r"(\d+)%", out)
        if m:
            return int(m.group(1))
        return -1
    except Exception as e:
        write_log(f"ERROR reading volume: {e}")
        return -1


def set_volume(percent):
    """Set master volume to percent (0-100). Returns diagnostic string."""
    percent = max(0, min(100, percent))
    try:
        before = get_volume()
        if before == percent:
            return f"already {percent}%"
        _run_pactl(["set-sink-volume", "@DEFAULT_SINK@", f"{percent}%"])
        after = get_volume()
        write_log(f"Volume set to {percent}% (readBack={after}%)")
        return f"set {before}%->{after}%"
    except Exception as e:
        write_log(f"ERROR setting volume: {e}")
        raise


def get_mute():
    """Return True if muted, False otherwise."""
    try:
        out = _run_pactl(["get-sink-mute", "@DEFAULT_SINK@"])
        # Output like: "Mute: yes" or "Mute: no"
        return "yes" in out.lower()
    except Exception as e:
        write_log(f"ERROR reading mute: {e}")
        return False


def set_mute(muted):
    """Set mute state. muted: bool."""
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
    """Get MAC of the default-route network interface."""
    try:
        # Find the interface used for the default route
        result = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True, text=True, timeout=5
        )
        m = re.search(r"dev\s+(\S+)", result.stdout)
        if not m:
            return ""
        iface = m.group(1)

        # Read its MAC address
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
    vol      = get_volume()
    muted    = get_mute()
    mute_int = "1" if muted else "0"
    ts       = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    mac      = get_mac_address()
    hostname = get_hostname()
    return f"VOLUME:{vol}\r\nMUTE:{mute_int}\r\nMAC:{mac}\r\nHOSTNAME:{hostname}\r\nUPDATED:{ts}\r\n"


# ============================================
# COMMAND ROUTER
# ============================================

def invoke_command(raw_message):
    write_log(f"CMD: {raw_message}")

    parts   = raw_message.split(":", 1)
    command = parts[0].upper().strip()
    value   = parts[1].strip() if len(parts) > 1 else ""

    if command == "VOLUME":
        try:
            pct = int(value)
            pct = max(0, min(100, pct))
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
        # Delay to allow HTTP response to complete
        Timer(1.0, _do_shutdown).start()

    else:
        write_log(f"WARNING: unknown command '{command}'")


def _do_shutdown():
    subprocess.run(["sudo", "shutdown", "now"], timeout=10)


# ============================================
# HTTP REQUEST HANDLER
# ============================================

class QSYSHandler(BaseHTTPRequestHandler):
    """Handles Q-SYS plugin HTTP requests."""

    # Suppress default stderr logging — we use our own log
    def log_message(self, format, *args):
        pass

    def _check_auth(self):
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {TOKEN}":
            write_log(f"AUTH FAIL from {self.client_address[0]}:{self.client_address[1]}")
            self._send(401, "Unauthorized")
            return False
        return True

    def _send(self, code, body="", content_type="text/plain; charset=utf-8"):
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
            body = get_status_body()
            self._send(200, body)

        elif path == "/command":
            # Q-SYS emulate mode sends GET with ?cmd= query string
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
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8").strip() if content_length > 0 else ""

            # Fall back to ?cmd= query string (Q-SYS emulate mode)
            if not body:
                qs = parse_qs(parsed.query)
                body = qs.get("cmd", [""])[0].strip()

            if body:
                # Send OK before processing (especially for SHUTDOWN)
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
    # Wait for audio subsystem to be ready (PipeWire/PulseAudio may start slowly)
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

    trim_log()

    server = HTTPServer(("0.0.0.0", PORT), QSYSHandler)
    write_log(f"=== WinPCControlServer (Linux) started on port {PORT} ===")
    print(f"WinPC Control Server listening on port {PORT}")

    # Graceful shutdown on SIGTERM (systemd sends this on stop)
    def handle_signal(signum, frame):
        write_log("=== WinPCControlServer stopped (signal) ===")
        server.shutdown()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        write_log("=== WinPCControlServer stopped ===")


if __name__ == "__main__":
    main()
