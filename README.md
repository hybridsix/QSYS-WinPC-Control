# Win PC Control - Q-SYS Plugin

**Author:** Michael King / Hybridsix
**Version:** 0.1
**Platform:** Q-SYS Designer 9.x+, Windows 10/11 target PC

A Q-SYS plugin that gives your Core direct control over a Windows PC on the local network - power, volume, mute, and live status, all from the schematic.

---

## Features

- **Wake-on-LAN** - power the PC on remotely via UDP magic packet (3 bursts on ports 7 and 9 for reliability)
- **Volume control** - read and set Windows master volume (integer 0-100), with configurable min/max limits and an out-of-range warning indicator
- **Mute** - toggle Windows master mute; restores pre-mute volume level on unmute
- **Graceful shutdown** - sends a clean shutdown command to Windows
- **Live status polling** - configurable poll interval keeps online state, volume, mute, and discovered hostname in sync
- **Auto MAC discovery** - the PC reports its own MAC address on every poll; the plugin writes it back to the MAC Address property so Wake-on-LAN works after a Core restart without manual configuration
- **Bearer token auth** - all HTTP traffic is protected by a random token generated at install time

---

## How it works

```
Q-SYS Core  ---- HTTP GET /status ---->  Windows PC
            <--- volume, mute, MAC,  ----
                 hostname, timestamp
            ---- HTTP POST /command -->  set volume / mute / shutdown
            ---- UDP :7,:9 (WOL) ----->  power on (3 bursts)
```

A small PowerShell HTTP server (`WinPCControlServer.ps1`) runs silently in the Windows user session at every logon, started by a Scheduled Task. It uses the Windows Core Audio API to read and set volume/mute, and responds to commands from the Q-SYS Core.

The Q-SYS plugin polls the server at a configurable interval (default 15 s) and tracks one of four states: **OFFLINE**, **BOOTING**, **ONLINE**, or **SHUTTING_DOWN**.

---

## Requirements

**Q-SYS Core side:**
- Q-SYS Designer 9.x or later
- Core must be on the same LAN as the Windows PC (or routed with UDP broadcast reach for WOL)

**Windows PC side:**
- Windows 10 or Windows 11
- PowerShell 5.1 (built-in)
- Must be configured to allow Wake-on-LAN in BIOS and network adapter settings
- A user account that logs in automatically or at startup (the server runs in the interactive session)

---

## Installation

### 1. Windows PC setup

The `windows-agent/` folder in this repo contains everything the PC needs.
Copy that folder (or just its contents) to the Windows PC, then run `install.ps1` **as Administrator**:

```powershell
.\install.ps1
```

To use a non-default port:
```powershell
.\install.ps1 -Port 2207
```

The installer will:
1. Create `C:\QSYS WinPC Control\` as the working directory
2. Copy `WinPCControlServer.ps1` into it
3. Generate a random 32-byte auth token and write it to `config.txt`
4. Register a URL ACL so the server can bind without elevation
5. Add a Windows Firewall rule (`WinPC Control HTTP`) for the chosen port
6. Create a Scheduled Task (`WinPC Control Server`) that starts the server at every user logon

At the end of the install, the token is printed to the console - **copy it**. You will need it in the next step.

To remove everything cleanly, run `uninstall.ps1` as Administrator.

### 2. Q-SYS Designer setup

1. Copy `QSYS WinPC Control.qplug` to:
   `%USERPROFILE%\Documents\QSC\Q-Sys Designer\Plugins\QSYS WinPC Control\`
2. Restart Q-SYS Designer (or use **Manage Plugins** to reload)
3. Drag **Hybridsix Plugins -> Win PC Control** from the component library onto your schematic
4. Open the plugin's **Properties** panel and fill in:

| Property | Value |
|---|---|
| Computer Name | A friendly label (e.g. `Presentation PC`) - shown on the block face |
| Hostname or IP | The PC's IP address or hostname (e.g. `192.168.1.50` or `studio-pc.local`) |
| MAC Address | Optional - leave blank; auto-discovered on first poll and written back to this property so it persists across Core restarts |
| HTTP Port | Must match the port used during `install.ps1` (default `2207`) |
| Auth Token | Paste the token printed by `install.ps1` |
| Poll Interval (s) | How often to check status (default `15` seconds) |

---

## Controls and pins

All pins are available in the **Control Pins** section of the Properties panel and can be enabled or disabled per-instance. Checked by default:

| Pin | Direction | Type | Description |
|---|---|---|---|
| Power On (WOL) | Input | Button | Sends a Wake-on-LAN magic packet |
| Shutdown | Input | Button | Sends a graceful shutdown command |
| Status Online | Output | LED | `true` when the server is reachable |
| Status Text | Output | Text | Current state: Offline / Booting... / Online / Shutting Down... |
| Last Poll | Output | Text | Timestamp of the last successful poll |
| Volume | Both | Fader (0-100) | Windows master volume |
| Mute | Both | Toggle button | Windows master mute |

---

## Volume limits

The plugin panel exposes **Vol Min** and **Vol Max** fields (default 0-100). The plugin clamps all volume commands to this range before sending them to the PC. If the PC's reported volume is outside the limits, the **Out of Range** LED lights amber.

This is useful when the PC is connected to a fixed-level system and you want to prevent the operator from going above or below a safe range.

---

## Security

- All HTTP requests carry an `Authorization: Bearer <token>` header
- The token is a cryptographically random 32-byte value, Base64-encoded (~43 characters)
- The token is stored in `C:\QSYS WinPC Control\config.txt` on the PC and must be copied manually into Q-SYS Designer - it is never transmitted in the clear during normal operation (only in HTTP headers, so use on a trusted LAN)
- The server only binds to the configured port - it does not listen on any other interface or port

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Status always shows Offline | Ping the PC from another device. Check the Firewall rule (`WinPC Control HTTP`). Verify the Scheduled Task is running. |
| Auth errors in the log | Token mismatch - re-copy the token from `config.txt` on the PC into the plugin's Auth Token property |
| WOL does not work | BIOS WOL must be enabled. NIC "Wake on Magic Packet" must be enabled in Device Manager. The Core must be on the same broadcast domain as the PC (or use a directed broadcast). |
| Volume changes do not stick | Check that no other application is overriding the Windows audio session. |
| Server does not start after reboot | Check Task Scheduler -> `WinPC Control Server`. Verify the task runs as the correct user and that the user account logs in automatically. |

---

## File reference

| File | Where | Purpose |
|---|---|---|
| `windows-agent/install.ps1` | Run on Windows PC (as Administrator) | One-time setup |
| `windows-agent/WinPCControlServer.ps1` | Copied to `C:\QSYS WinPC Control\` by installer | The HTTP server - do not run manually |
| `windows-agent/uninstall.ps1` | Run on Windows PC (as Administrator) | Clean removal |
| `QSYS WinPC Control.qplug` | Q-SYS Designer plugins folder | The compiled plugin |
| `C:\QSYS WinPC Control\config.txt` | Windows PC | PORT= and TOKEN= - do not edit manually |
| `C:\QSYS WinPC Control\server.log` | Windows PC | Rolling server log (capped at 500 lines) |

---

## License

MIT - see repository for details.