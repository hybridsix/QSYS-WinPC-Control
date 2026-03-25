# Win PC Control - Windows Agent

This folder contains the files that run on the Windows PC being controlled.

## What to do

1. Copy this entire folder (or just the three files below) to the Windows PC
2. Right-click `install.ps1` and choose "Run with PowerShell" - or open an
   Administrator PowerShell and run it from wherever you copied it:

   ```powershell
   .\install.ps1
   ```

3. When the script finishes, it will print an auth token. Copy it.
4. Paste that token into the Auth Token property in Q-SYS Designer.

That is all you need to do on the PC. The server starts automatically at every logon.

## Files

| File | Purpose |
|---|---|
| `install.ps1` | One-time setup - run as Administrator |
| `WinPCControlServer.ps1` | The HTTP server - do not run manually, the installer handles it |
| `uninstall.ps1` | Removes everything install.ps1 created - run as Administrator |

## Optional: custom port

The default port is 2207. To use a different port:

```powershell
.\install.ps1 -Port 8080
```

Make sure the same port number is set in the plugin's HTTP Port property in Q-SYS Designer.

## Removing

To cleanly remove the server, firewall rule, scheduled task, and working directory:

```powershell
.\uninstall.ps1
```

For full details see the main [README](../README.md).