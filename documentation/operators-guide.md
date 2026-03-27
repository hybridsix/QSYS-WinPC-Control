# Win PC Control - Operator's Guide

**Plugin:** Hybridsix Plugins -> Win PC Control
**Version:** 0.2.0-alpha

This guide is for AV technicians and system operators who are using an installed and configured Win PC Control plugin in a Q-SYS design. For installation and setup, refer to the [README](../README.md).

---

## What this plugin does

Win PC Control lets a Q-SYS Core manage a Windows PC on the same network. From the plugin panel or from wired controls in your design, you can:

- **Turn the PC on** (Wake-on-LAN - works even when the PC is off)
- **Shut the PC down** gracefully
- **Control the Windows master volume** (the same level as the speaker icon in the system tray)
- **Mute and unmute** the PC audio
- **See whether the PC is online** and what state it's in

---

## The Control panel

Double-click the plugin block in the schematic to open the panel. It has two tabs: **Control** and **Setup**.

### Control tab

```
+------------------- Power Control -------------------+
|  [ Power On (WOL) ]          [ Shutdown ]           |
+-----------------------------------------------------+

+------------------- Connection Status ---------------+
|  Status:  * [Online / Offline / Booting...]         |
|  PC Name: [studio-pc.local]                         |
|  Last Poll: [10:42:15]                              |
+-----------------------------------------------------+

+------------------- Audio ---------------------------+
|  Volume: --------*--------  [ Mute ]               |
|  Vol Min: [0]   Vol Max: [100]   Out of range: o   |
+-----------------------------------------------------+
```

#### Power Control

| Button | What it does |
|---|---|
| **Power On (WOL)** | Sends a Wake-on-LAN magic packet to the PC's MAC address (3 bursts on both ports 7 and 9 for reliability). Works from any state, including when the PC is off. If the PC is already **Online**, the magic packet is still sent but the status stays **Online** so volume/mute controls keep working. Otherwise, the status changes to **Booting...** and then to **Online** once the PC is up (typically 30-60 seconds). If the PC doesn't come online within 120 seconds, the status automatically returns to **Offline**. |
| **Shutdown** | Sends a graceful shutdown command to Windows. Only works when the PC is **Online**. The status changes to **Shutting Down...** and then to **Offline** once the server stops responding. |

#### Connection Status

| Field | What it shows |
|---|---|
| **Status LED + text** | The current PC state - see [States](#states) below |
| **PC Name** | The Windows hostname reported by the PC (auto-discovered, not the Computer Name property) |
| **Last Poll** | Time of the last successful response from the PC. If this is stale, the PC may have gone offline between polls. |

#### Audio

| Control | What it does |
|---|---|
| **Volume fader** | Sets Windows master volume (0-100). Changes are rate-limited (max 10 per second) to prevent overload. The fader also moves automatically when the PC volume changes from another source (synced on each poll). A digit entry box next to the fader lets you type an exact volume value. |
| **Mute button** | Toggles Windows master mute (red = muted). |
| **Vol Min / Vol Max** | Clamps the volume range. Commands outside this range are automatically clamped. The fader is also clamped. |
| **Out of Range LED** | Lights amber if the PC is reporting a volume level outside the Min/Max limits you've set. |

---

## States

The plugin tracks the PC through four states:

| State | LED | Meaning |
|---|---|---|
| **Offline** | Red/off | The PC is not responding. It is either powered off, the server is not running, or there's a network issue. |
| **Booting...** | Amber | Wake-on-LAN was just sent. The plugin is waiting for the server to come up. Poll failures are normal here. |
| **Online** | Green | The server is responding. Volume and mute are live. All commands work. |
| **Shutting Down...** | Amber | A shutdown command was accepted. The plugin is waiting for the PC to stop responding. |

Note: Volume and mute commands are silently ignored when the PC is not **Online**. Power On works from any state.

---

## Setup tab

The Setup tab shows the current configuration. Fields are visually split into two groups:

**Grey fields (auto-populated)** — these are populated from Properties on startup and updated automatically (e.g., MAC Address is discovered on each poll). They cannot be changed at runtime from this page; edit them in the Properties panel instead.

| Field | What it shows |
|---|---|
| Computer Name | The friendly label set in Properties |
| Hostname / IP | The address the plugin connects to |
| MAC Address | Used for Wake-on-LAN — auto-discovered after first poll and saved to the property automatically |
| Auth Token | The bearer token for HTTP authentication |

**Cyan-bordered fields (editable at runtime)** — you can change these while the plugin is running and press the **Update** button to apply.

| Field | What it does |
|---|---|
| HTTP Port | The port the server is listening on (default 2207) |
| Poll Interval (s) | How often the plugin checks in with the PC (default 15s) |

The **Update** button writes your changes back to the plugin Properties, re-derives the connection URL, and restarts the poll timer. Changes to other fields (Computer Name, Hostname, Auth Token) must be made in the Properties panel and require a plugin restart.

If Auth Token is blank, the plugin cannot communicate with the PC. Re-run `install.ps1` from the `windows-agent/` folder on the PC and paste the generated token into the Auth Token property.

---

## Common situations

### The PC won't wake up

1. Confirm the PC was previously online at least once (so the MAC is cached), or check that MAC Address is set in Properties
2. Check that Wake-on-LAN is enabled in the PC's BIOS and in Device Manager under the network adapter properties
3. The Q-SYS Core must be on the same network segment as the PC for WOL broadcast to reach it - check with your network administrator if they're on different VLANs

### Volume is jumping back

The plugin polls the PC every N seconds and syncs the volume back to Q-SYS. If another application or Windows itself is changing the volume, you'll see the fader move. This is expected - the plugin reflects the true Windows master volume level.

### The Out of Range LED is lit

The PC is reporting a volume level outside the Vol Min / Vol Max range you've configured. This is informational - the plugin doesn't force the PC's volume back into range on its own (it only clamps commands you send). If this is persistent, adjust the Min/Max values or check if something else is setting the PC volume.

### Status is stuck on Booting...

The plugin has a 120-second safety timeout — if the PC doesn't come online within 2 minutes of a WOL, the status automatically returns to **Offline**. If this keeps happening, check:
- The user account is logged in (the server requires an active user session)
- Task Scheduler -> `WinPC Control Server` task exists and is enabled
- No error in `C:\QSYS WinPC Control\server.log` on the PC

### The plugin shows Online but volume/mute don't respond

Check that the Auth Token in the plugin Properties matches the token in `C:\QSYS WinPC Control\config.txt` on the PC. A mismatch causes commands to be rejected with a 401 error - the plugin may still show Online from a cached state.

---

## Control pins

If your design is wired to control this plugin from UCI buttons, a touch panel, or other Q-SYS components, the integrator will have connected some or all of these pins:

| Pin name | Direction | What to send |
|---|---|---|
| Power On (WOL) | Input | Momentary trigger (Boolean pulse) |
| Shutdown | Input | Momentary trigger (Boolean pulse) |
| Status Online | Output | Boolean - `true` = Online |
| Status Text | Output | String - current state label |
| Last Poll | Output | String - timestamp |
| Volume | Both | Float 0-100 |
| Mute | Both | Boolean - `true` = muted |

---

## Maintenance

**Server log:** `C:\QSYS WinPC Control\server.log` on the Windows PC. Capped at 500 lines, oldest entries are dropped automatically.

**Restarting the server manually:** Open Task Scheduler on the PC, find `WinPC Control Server`, and click **Run**. Or simply log out and back in.

**Updating the plugin:** Replace the `.qplug` file in the Q-SYS Designer plugins folder and reload the design. Existing property values (IP, token, etc.) are preserved as long as the plugin GUID hasn't changed.

**Updating the server script:** Copy the new `WinPCControlServer.ps1` from `windows-agent/` to `C:\QSYS WinPC Control\` on the PC and restart the task. The auth token and port are preserved in `config.txt` - no need to re-run `install.ps1` for script-only updates.