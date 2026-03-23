# ============================================================
# WinPCControl.ps1
# Windows-side audio control script for Q-SYS integration
#
# Triggered by Windows Scheduled Task on Event ID 9001.
# Runs in the interactive user session for audio API access.
#
# Commands (via Windows Event Log message payload):
#   VOLUME:0-100    Set master volume
#   MUTE:1 / MUTE:0 Mute / unmute
#   QUERY:VOLUME    Force a status file refresh
#
# Version: 0.2
# ============================================================


# ===============================================
# CONFIGURATION
# ===============================================

$STATUS_FILE  = "C:\QSYS WinPC Control\status.txt"
$LOG_FILE     = "C:\QSYS WinPC Control\winpccontrol.log"
$EVENT_SOURCE = "WinPCControl"
$EVENT_LOG    = "Application"
$EVENT_ID_IN  = 9001          # Q-SYS sends commands on this Event ID
$EVENT_ID_OUT = 9002          # Reserved for future event-based status reporting


# -------------------------------------------
# LOGGING
# -------------------------------------------

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Add-Content -Path $LOG_FILE -Value $entry
}


# ================================================================
# WINDOWS CORE AUDIO API
# Inline C# wrapping IAudioEndpointVolume -- no third-party deps.
# ================================================================

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

// COM interface definitions (Windows Core Audio API)
// Only methods we actually call are declared; partial COM interfaces are valid.

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
    int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
    int GetMasterVolumeLevelScalar(out float pfLevel);
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

// AudioHelper: public API used by this script
public static class AudioHelper {

    // Get the default audio playback endpoint's volume interface
    private static IAudioEndpointVolume GetVolumeInterface() {
        var enumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(enumeratorType);

        // eRender = 0 (playback), eMultimedia = 1 (role)
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 1, out device);

        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object volumeObj;
        device.Activate(ref iid, 1, IntPtr.Zero, out volumeObj);

        return (IAudioEndpointVolume)volumeObj;
    }

    // Set master volume: 0-100 int, converted to 0.0-1.0 scalar
    public static void SetVolume(int percent) {
        var vol = GetVolumeInterface();
        float scalar = Math.Max(0f, Math.Min(1f, percent / 100f));
        Guid empty = Guid.Empty;
        vol.SetMasterVolumeLevelScalar(scalar, ref empty);
    }

    // Get master volume: returns 0-100 int
    public static int GetVolume() {
        var vol = GetVolumeInterface();
        float scalar;
        vol.GetMasterVolumeLevelScalar(out scalar);
        return (int)Math.Round(scalar * 100);
    }

    // Set mute
    public static void SetMute(bool muted) {
        var vol = GetVolumeInterface();
        Guid empty = Guid.Empty;
        vol.SetMute(muted, ref empty);
    }

    // Get mute
    public static bool GetMute() {
        var vol = GetVolumeInterface();
        bool muted;
        vol.GetMute(out muted);
        return muted;
    }
}
"@


# ============================================
# VOLUME AND MUTE FUNCTIONS
# ============================================

function Set-MasterVolume {
    param([int]$Percent)
    try {
        [AudioHelper]::SetVolume($Percent)
        Write-Log "Volume set to $Percent%"
    }
    catch {
        Write-Log "ERROR setting volume: $_"
        throw
    }
}

function Get-MasterVolume {
    try {
        return [AudioHelper]::GetVolume()
    }
    catch {
        Write-Log "ERROR reading volume: $_"
        return -1   # Q-SYS treats -1 as unknown
    }
}

function Set-MasterMute {
    param([bool]$Muted)
    try {
        [AudioHelper]::SetMute($Muted)
        $state = if ($Muted) { "MUTED" } else { "UNMUTED" }
        Write-Log "Mute state set to: $state"
    }
    catch {
        Write-Log "ERROR setting mute: $_"
        throw
    }
}

function Get-MasterMute {
    try {
        return [AudioHelper]::GetMute()
    }
    catch {
        Write-Log "ERROR reading mute state: $_"
        return $false   # Fail open - assume unmuted if we can't read
    }
}


# -----------------------------------------------
# STATUS FILE
# Written after every command execution.
#
# Atomic write (temp + rename) prevents partial reads.
# -----------------------------------------------

function Update-StatusFile {
    try {
        $volume    = Get-MasterVolume
        $muteRaw   = Get-MasterMute
        $mute      = if ($muteRaw) { "1" } else { "0" }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $content = "VOLUME:$volume`r`nMUTE:$mute`r`nUPDATED:$timestamp`r`n"

        # Atomic write - prevents partial reads by Q-SYS
        $tempPath = "$STATUS_FILE.tmp"
        Set-Content -Path $tempPath -Value $content -NoNewline
        Move-Item -Path $tempPath -Destination $STATUS_FILE -Force

        Write-Log "Status file updated - Volume:$volume% Mute:$mute"
    }
    catch {
        Write-Log "ERROR updating status file: $_"
    }
}


# ================================================================
# EVENT LOG READER
# Retrieves the most recent command sent by Q-SYS (Event ID 9001)
# ================================================================

function Get-LatestCommand {
    try {
        $event = Get-EventLog `
            -LogName   $EVENT_LOG `
            -Source    $EVENT_SOURCE `
            -InstanceId $EVENT_ID_IN `
            -Newest    1 `
            -ErrorAction Stop

        if (-not $event) {
            Write-Log "ERROR: No matching event found in log"
            exit 1
        }

        return $event.Message.Trim()
    }
    catch {
        Write-Log "ERROR reading event log: $_"
        exit 1
    }
}


# ============================================================
# COMMAND ROUTER
# Parses "COMMAND:VALUE" and dispatches to handler functions.
# ============================================================

function Invoke-QSYSCommand {
    param([string]$RawMessage)

    Write-Log "Received: $RawMessage"

    # Split on first colon only - value might theoretically contain colons later
    $parts   = $RawMessage -split ":", 2
    $command = $parts[0].ToUpper().Trim()
    $value   = if ($parts.Length -gt 1) { $parts[1].Trim() } else { "" }

    switch ($command) {

        "VOLUME" {
            # Validate that value is a number in range before acting
            $percent = 0
            if ([int]::TryParse($value, [ref]$percent)) {
                $percent = [Math]::Max(0, [Math]::Min(100, $percent))
                Set-MasterVolume -Percent $percent
            }
            else {
                Write-Log "ERROR: Invalid volume value received: '$value'"
            }
        }

        "MUTE" {
            if ($value -eq "1") {
                Set-MasterMute -Muted $true
            }
            elseif ($value -eq "0") {
                Set-MasterMute -Muted $false
            }
            else {
                Write-Log "ERROR: Invalid mute value received: '$value' (expected 0 or 1)"
            }
        }

        "QUERY" {
            # No action needed - Update-StatusFile runs unconditionally at the end
            # This command exists so Q-SYS can explicitly request a fresh status read
            Write-Log "Status query received - refreshing status file"
        }

        default {
            Write-Log "WARNING: Unknown command '$command' - ignored"
        }
    }
}


# ----------------------------
# MAIN
# ----------------------------

Write-Log "=== WinPCControl triggered ==="

# Ensure working directory exists
$workDir = "C:\QSYS WinPC Control"
if (-not (Test-Path $workDir)) {
    try {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        Write-Log "Created working directory: $workDir"
    }
    catch {
        # If we can't create the directory we can't log either - just exit
        exit 1
    }
}

# Retrieve and route the incoming command
$rawCommand = Get-LatestCommand
Invoke-QSYSCommand -RawMessage $rawCommand

# Always refresh the status file after any command
# This keeps Q-SYS feedback current regardless of what was requested
Update-StatusFile

Write-Log "=== WinPCControl complete ==="
