# Win PC Control - Operator's Guide

**Plugin:** Hybridsix Plugins -> Win PC Control
**Version:** 0.1

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
| **Power On (WOL)** | Sends a Wake-on-LAN magic packet to the PC's MAC address. Works from any state, including when the PC is off. The status will change to **Booting...** and then to **Online** once the PC is up (typically 30-60 seconds). |
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
| **Volume fader** | Sets Windows master volume (0-100). Moves automatically when the PC volume changes from another source. |
| **Mute button** | Toggles Windows master mute (red = muted). When you unmute, the volume is restored to what it was before muting. |
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

The Setup tab shows a read-only summary of the current configuration. If something looks wrong here, the values need to be corrected in the plugin's **Properties** panel (right-click the block -> Properties, or click the block and view the Properties pane).

| Field | What it shows |
|---|---|
| Computer Name | The friendly label set in Properties |
| Hostname / IP | The address the plugin connects to |
| MAC Address | Used for Wake-on-LAN - auto-discovered after first poll and saved to the property automatically |
| HTTP Port | The port the server is listening on (default 2207) |
| Poll Interval (s) | How often the plugin checks in with the PC |
| Auth Token | Shows **(configured)** or **NOT SET** |

If Auth Token shows **NOT SET**, the plugin cannot communicate with the PC. Re-run `install.ps1` on the PC and paste the generated token into the Auth Token property.

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

The PC may have woken up but the server didn't start. Check:
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

**Updating the server script:** Copy the new `WinPCControlServer.ps1` to `C:\QSYS WinPC Control\` on the PC and restart the task. The auth token and port are preserved in `config.txt` - no need to re-run `install.ps1` for script-only updates.