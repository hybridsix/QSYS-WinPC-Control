# ================================================================
# WinPCControlServer.ps1
# Persistent HTTP control server for Q-SYS WinPC Control plugin.
#
# Runs in the interactive user session (required for audio API).
# Started at logon by a Scheduled Task installed by install.ps1.
#
# Endpoints (all require Authorization: Bearer <token>):
#   GET  /status    Returns current volume, mute state, timestamp
#   POST /command   Accepts VOLUME:N  MUTE:0  MUTE:1  SHUTDOWN
#
# Config: C:\QSYS WinPC Control\config.txt  (PORT=, TOKEN=)
# Log:    C:\QSYS WinPC Control\server.log
#
# Version: 0.1
# ================================================================


# ============================================
# CONFIGURATION
# ============================================

$WORK_DIR   = "C:\QSYS WinPC Control"
$CONFIG_FILE = "$WORK_DIR\config.txt"
$LOG_FILE    = "$WORK_DIR\server.log"

function Read-Config {
    $cfg = @{ Port = 2207; Token = "" }
    if (Test-Path $CONFIG_FILE) {
        Get-Content $CONFIG_FILE | ForEach-Object {
            if ($_ -match "^(\w+)=(.+)$") {
                $cfg[$matches[1]] = $matches[2].Trim()
            }
        }
    }
    return $cfg
}

$Config = Read-Config
$Port   = [int]$Config.Port
$Token  = $Config.Token

if ($Token -eq "") {
    Write-Host "ERROR: No auth token found in $CONFIG_FILE. Run install.ps1 first."
    exit 1
}


# ============================================
# CONSOLE WINDOW SETUP
# ============================================

$Host.UI.RawUI.WindowTitle = "WinPC Control Server - DO NOT CLOSE"

$script:lastQsysContact = $null
$script:statusLines = [System.Collections.Generic.List[string]]::new()
$STATUS_MAX_LINES = 8
$script:statusStartRow = 0   # Set after banner is drawn

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "    WinPC Control Server" -ForegroundColor White
    Write-Host "    DO NOT CLOSE THIS WINDOW" -ForegroundColor Yellow
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Port:     $Port" -ForegroundColor Gray
    Write-Host "  Host:     $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "  User:     $env:USERNAME" -ForegroundColor Gray
    Write-Host "  Log:      $LOG_FILE" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  This server allows a Q-SYS Core to control" -ForegroundColor DarkGray
    Write-Host "  volume, mute, and power on this PC." -ForegroundColor DarkGray
    Write-Host "  Closing this window will stop the server." -ForegroundColor DarkGray
    Write-Host ""
    # Record cursor row — all status lines will be drawn from here down
    $script:statusStartRow = $Host.UI.RawUI.CursorPosition.Y
}

function Update-ConsoleStatus {
    param([string]$Event = "poll")

    $ts = Get-Date -Format "HH:mm:ss"

    if ($Event -eq "poll") {
        $script:lastQsysContact = Get-Date
        $script:statusLines.Add("  [$ts]  Q-SYS poll received")
    }
    elseif ($Event -eq "command") {
        $script:statusLines.Add("  [$ts]  Q-SYS command received")
    }

    # Keep only the last N lines
    while ($script:statusLines.Count -gt $STATUS_MAX_LINES) {
        $script:statusLines.RemoveAt(0)
    }

    # Update title bar with elapsed time (useful from taskbar)
    if ($script:lastQsysContact) {
        $elapsed = (Get-Date) - $script:lastQsysContact
        if ($elapsed.TotalSeconds -lt 60) {
            $ago = "{0}s ago" -f [int]$elapsed.TotalSeconds
        } else {
            $ago = "{0}m ago" -f [int]$elapsed.TotalMinutes
        }
        $Host.UI.RawUI.WindowTitle = "WinPC Control - Connected (last poll $ago)"
    } else {
        $Host.UI.RawUI.WindowTitle = "WinPC Control - Waiting for Q-SYS..."
    }

    # Overwrite status area in place — no Clear-Host, no flicker
    $width = $Host.UI.RawUI.BufferSize.Width
    $blank = " " * $width
    for ($i = 0; $i -lt $STATUS_MAX_LINES; $i++) {
        [Console]::SetCursorPosition(0, $script:statusStartRow + $i)
        if ($i -lt $script:statusLines.Count) {
            $line = $script:statusLines[$i]
            Write-Host $line.PadRight($width) -ForegroundColor Green -NoNewline
        } else {
            [Console]::Write($blank)
        }
    }
    [Console]::SetCursorPosition(0, $script:statusStartRow + $STATUS_MAX_LINES)
}


# -----------------------------------------------
# LOGGING
# Max log size capped at $LOG_MAX_LINES lines.
# Trimmed on startup and every 100 writes.
# -----------------------------------------------

$LOG_MAX_LINES       = 500
$script:_logWriteCount = 0

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LOG_FILE -Value "[$ts] $Message"
    $script:_logWriteCount++
    if ($script:_logWriteCount % 100 -eq 0) { Trim-Log }
}

function Trim-Log {
    if (-not (Test-Path $LOG_FILE)) { return }
    $lines = Get-Content -Path $LOG_FILE -ErrorAction SilentlyContinue
    if ($lines.Count -gt $LOG_MAX_LINES) {
        $trimmed = $lines | Select-Object -Last $LOG_MAX_LINES
        Set-Content -Path $LOG_FILE -Value $trimmed
    }
}


# ============================================================
# WINDOWS CORE AUDIO API  (inline C#, no third-party deps)
# ============================================================

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid iid, uint dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    int OpenPropertyStore(uint stgmAccess, out IntPtr ppProperties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out uint pdwState);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(uint dataFlow, uint dwStateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(uint dataFlow, uint role, out IMMDevice ppEndpoint);
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out uint pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(ref Guid pguidEventContext);
    int VolumeStepDown(ref Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

public static class AudioHelper {
    private static IAudioEndpointVolume GetVolumeInterface() {
        var enumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(enumeratorType);
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 1, out device);
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object volumeObj;
        device.Activate(ref iid, 1, IntPtr.Zero, out volumeObj);
        return (IAudioEndpointVolume)volumeObj;
    }

    private static bool scalarWorks = true;

    public static string SetVolume(int percent) {
        var vol = GetVolumeInterface();
        Guid empty = Guid.Empty;

        float beforeScalar;
        vol.GetMasterVolumeLevelScalar(out beforeScalar);
        int beforePct = (int)Math.Round(beforeScalar * 100);

        if (beforePct == percent) return string.Format("already {0}%", percent);

        // Try scalar API if not known-broken on this hardware.
        if (scalarWorks) {
            float scalar = Math.Max(0f, Math.Min(1f, percent / 100f));
            vol.SetMasterVolumeLevelScalar(scalar, ref empty);

            float afterScalar;
            vol.GetMasterVolumeLevelScalar(out afterScalar);
            int afterPct = (int)Math.Round(afterScalar * 100);

            if (afterPct == percent) {
                return string.Format("scalar {0}%->{1}%", beforePct, afterPct);
            }
            // Scalar returned S_OK but didn't change volume — driver ignores it.
            if (afterPct == beforePct) {
                scalarWorks = false;
            }
        }

        // Step-based control (works on all hardware, ~2% resolution).
        uint currentStep, stepCount;
        vol.GetVolumeStepInfo(out currentStep, out stepCount);

        float nowScalar;
        vol.GetMasterVolumeLevelScalar(out nowScalar);
        int currentPct = (int)Math.Round(nowScalar * 100);
        int delta = percent - currentPct;

        float pctPerStep = stepCount > 0 ? 100f / stepCount : 2f;
        int steps = (int)Math.Round(Math.Abs(delta) / pctPerStep);
        if (steps < 1) steps = 1;
        if (steps > 100) steps = 100;

        for (int i = 0; i < steps; i++) {
            if (delta > 0) vol.VolumeStepUp(ref empty);
            else           vol.VolumeStepDown(ref empty);
        }

        float finalScalar;
        vol.GetMasterVolumeLevelScalar(out finalScalar);
        int finalPct = (int)Math.Round(finalScalar * 100);
        return string.Format("step {0}%->{1}%  ({2} steps)",
            beforePct, finalPct, steps);
    }

    public static int GetVolume() {
        var vol = GetVolumeInterface();
        float scalar;
        vol.GetMasterVolumeLevelScalar(out scalar);
        return (int)Math.Round(scalar * 100);
    }

    public static void SetMute(bool muted) {
        var vol = GetVolumeInterface();
        Guid empty = Guid.Empty;
        vol.SetMute(muted, ref empty);
    }

    public static bool GetMute() {
        var vol = GetVolumeInterface();
        bool muted;
        vol.GetMute(out muted);
        return muted;
    }
}
"@


# ----------------------------
# AUDIO HELPERS
# ----------------------------

function Get-MasterVolume {
    try   { return [AudioHelper]::GetVolume() }
    catch { Write-Log "ERROR reading volume: $_"; return -1 }
}

function Get-MasterMute {
    try   { return [AudioHelper]::GetMute() }
    catch {
        Write-Log "ERROR reading mute: $_"
        return $false
    }
}

function Set-MasterVolume ([int]$Percent) {
    try {
        $diag = [AudioHelper]::SetVolume($Percent)
        $readBack = [AudioHelper]::GetVolume()
        Write-Log "Volume set to $Percent% (readBack=$readBack%) [$diag]"
    }
    catch { Write-Log "ERROR setting volume: $_"; throw }
}

function Set-MasterMute ([bool]$Muted) {
    try   { [AudioHelper]::SetMute($Muted); Write-Log "Mute set to $Muted" }
    catch { Write-Log "ERROR setting mute: $_"; throw }
}


# ============================================================
# COMMAND ROUTER
# ============================================================

function Invoke-QSYSCommand {
    param([string]$RawMessage)

    Write-Log "CMD: $RawMessage"

    $parts   = $RawMessage -split ":", 2
    $command = $parts[0].ToUpper().Trim()
    $value   = if ($parts.Length -gt 1) { $parts[1].Trim() } else { "" }

    switch ($command) {
        "VOLUME" {
            $pct = 0
            if ([int]::TryParse($value, [ref]$pct)) {
                $pct = [Math]::Max(0, [Math]::Min(100, $pct))
                Set-MasterVolume -Percent $pct
            } else {
                Write-Log "ERROR: bad volume value '$value'"
            }
        }
        "MUTE" {
            if ($value -eq "1")     { Set-MasterMute -Muted $true  }
            elseif ($value -eq "0") { Set-MasterMute -Muted $false }
            else { Write-Log "ERROR: bad mute value '$value'" }
        }
        "SHUTDOWN" {
            Write-Log "Shutdown command received - initiating"
            Start-Sleep -Seconds 1   # Allow HTTP response to complete first
            & shutdown /s /f /t 0
        }
        "QUERY" {
            # No-op - status is always returned in the response body
            Write-Log "QUERY received"
        }
        default {
            Write-Log "WARNING: unknown command '$command'"
        }
    }
}


# ===============================================
# HTTP RESPONSE HELPERS
# ===============================================

function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$Body    = "",
        [string]$ContentType = "text/plain; charset=utf-8"
    )
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    if ($Body -ne "") {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    $Response.OutputStream.Close()
}

function Get-MacAddress {
    try {
        $mac = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } |
                Sort-Object -Property Speed -Descending |
                Select-Object -First 1).MacAddress
        # Normalise to XX:XX:XX:XX:XX:XX
        return $mac -replace '-', ':'
    }
    catch {
        return ""
    }
}

function Get-StatusBody {
    $vol      = Get-MasterVolume
    $muted    = Get-MasterMute
    $muteInt  = if ($muted) { "1" } else { "0" }
    $ts       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $mac      = Get-MacAddress
    $hostname = $env:COMPUTERNAME
    return "VOLUME:$vol`r`nMUTE:$muteInt`r`nMAC:$mac`r`nHOSTNAME:$hostname`r`nUPDATED:$ts`r`n"
}


# ================================================================
# HTTP LISTENER LOOP
# ================================================================

# Ensure work dir exists
if (-not (Test-Path $WORK_DIR)) {
    New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null
}

# Wait for the Windows audio subsystem to be ready (can take a few seconds at logon)
$audioReady = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $null = [AudioHelper]::GetVolume()
        $audioReady = $true
        break
    }
    catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $audioReady) {
    Write-Log "WARNING: Audio subsystem not ready after 30 seconds - volume/mute may not work"
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:$Port/")

try {
    $listener.Start()
    Write-Log "=== WinPCControlServer started on port $Port ==="
    Trim-Log   # Trim any leftover growth from previous run
    Show-Banner
    Write-Host "  Waiting for Q-SYS connection..." -ForegroundColor Yellow
}
catch {
    Write-Log "FATAL: Could not start HTTP listener on port $Port. Was install.ps1 run as admin? Error: $_"
    exit 1
}

Write-Log "Waiting for requests..."

while ($listener.IsListening) {
    try {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        $method = $request.HttpMethod.ToUpper()
        $path   = $request.Url.AbsolutePath.ToLower().TrimEnd("/")

        Write-Log "$method $path from $($request.RemoteEndPoint)"

        # ---- Auth check ----
        $authHeader = $request.Headers["Authorization"]
        if ($authHeader -ne "Bearer $Token") {
            Write-Log "AUTH FAIL from $($request.RemoteEndPoint)"
            Send-Response -Response $response -StatusCode 401 -Body "Unauthorized"
            continue
        }

        # ---- Route ----
        if ($path -eq "/status" -and $method -eq "GET") {
            $body = Get-StatusBody
            Send-Response -Response $response -Body $body
            Update-ConsoleStatus -Event "poll"
        }
        elseif ($path -eq "/command" -and ($method -eq "POST" -or $method -eq "GET")) {
            $reader  = [System.IO.StreamReader]::new($request.InputStream, [System.Text.Encoding]::UTF8)
            $cmdBody = $reader.ReadToEnd().Trim()
            $reader.Dispose()

            # Fall back to ?cmd= query string (Q-SYS emulate mode sends GET with no body)
            if ($cmdBody -eq "") {
                $cmdBody = [System.Uri]::UnescapeDataString(
                    ($request.QueryString["cmd"] -replace '\+', ' ')
                ).Trim()
            }

            if ($cmdBody -ne "") {
                # Send OK before SHUTDOWN so Q-SYS gets the response
                Send-Response -Response $response -Body "OK"
                Invoke-QSYSCommand -RawMessage $cmdBody
                Update-ConsoleStatus -Event "command"
            } else {
                Send-Response -Response $response -StatusCode 400 -Body "Empty command"
            }
        }
        else {
            Send-Response -Response $response -StatusCode 404 -Body "Not found"
        }
    }
    catch [System.Net.HttpListenerException] {
        # Normal on listener.Stop() - exit cleanly
        break
    }
    catch {
        Write-Log "ERROR handling request: $_"
        try { $context.Response.Abort() } catch {}
    }
}

Write-Log "=== WinPCControlServer stopped ==="
