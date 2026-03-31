# Remote PC Control - Ubuntu Agent

HTTP control server that lets a Q-SYS Core remotely control volume, mute, and power on an Ubuntu 24.04 LTS PC.

## Requirements

- Ubuntu 24.04 LTS (PipeWire + PulseAudio compatibility layer)
- Python 3 (pre-installed)
- `pactl` (from `pulseaudio-utils`, installed automatically)
- A user session with audio access (the service runs as your user, not root)

## Quick Start

1. Copy the `ubuntu-agent/` folder to the target Ubuntu PC.

2. Run the installer with sudo:
   ```bash
   cd ubuntu-agent
   sudo bash install.sh
   ```

3. Copy the displayed auth token into the Q-SYS plugin's **Auth Token** property.

4. Enter the PC's IP address in the plugin's **Hostname or IP** property.

That's it. The server starts immediately and auto-starts on every boot.

## What the installer does

| Step | Action |
|------|--------|
| 1 | Installs `python3` and `pulseaudio-utils` if missing |
| 2 | Creates `/opt/qsys-remotepc-control/` working directory |
| 3 | Copies the server script and uninstall script |
| 4 | Generates a random 32-byte Base64 auth token |
| 5 | Adds a sudoers rule for passwordless `shutdown` |
| 6 | Opens the HTTP port in UFW firewall |
| 7 | Creates and starts a systemd user service |

## Custom port or pre-set token

```bash
sudo bash install.sh 8080                    # Custom port
sudo bash install.sh 2207 "mytoken123"       # Custom port + token
```

Default port: **2207** (same as the Windows agent).

## Managing the service

```bash
# Check status
systemctl --user status remotepc-control

# View live logs
journalctl --user -u remotepc-control -f

# Restart
systemctl --user restart remotepc-control

# Stop
systemctl --user stop remotepc-control
```

## Log file

Server logs are written to `/opt/qsys-remotepc-control/server.log` and automatically trimmed to 500 lines.

## Uninstalling

```bash
sudo bash /opt/qsys-remotepc-control/uninstall.sh
```

This removes the systemd service, firewall rule, sudoers entry, and the working directory.

## Protocol compatibility

The Ubuntu agent is protocol-identical to the Windows agent. The Q-SYS plugin doesn't need any changes - it works with either agent transparently:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/status` | GET | Returns `VOLUME:N`, `MUTE:0/1`, `MAC:xx:xx:xx:xx:xx:xx`, `HOSTNAME:name`, `UPDATED:timestamp` |
| `/command` | POST (or GET with `?cmd=`) | Accepts `VOLUME:N`, `MUTE:0`, `MUTE:1`, `SHUTDOWN` |

All requests require `Authorization: Bearer <token>` header.

## Troubleshooting

**"Audio subsystem not ready" warning:**
The server waits up to 30 seconds for PipeWire/PulseAudio at startup. If audio still isn't available, check that PipeWire is running: `systemctl --user status pipewire`

**Volume commands have no effect:**
Make sure `pactl` works from your user session: `pactl get-sink-volume @DEFAULT_SINK@`. If it fails, PipeWire or PulseAudio may not be running for your user.

**Shutdown doesn't work:**
Verify the sudoers rule exists: `sudo cat /etc/sudoers.d/remotepc-control`. If missing, re-run `install.sh`.
