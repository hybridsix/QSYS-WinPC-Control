# ============================================================
# install.ps1
# One-time setup for WinPC Control on a Windows 11 PC.
# Run as Administrator. Run once per machine / per user account.
#
# Version: 0.1
# ============================================================

#Requires -RunAsAdministrator

param(
    [int]$Port = 2207
)

$WORK_DIR      = "C:\QSYS WinPC Control"
$SERVER_SCRIPT = "WinPCControlServer.ps1"
$CONFIG_FILE   = "$WORK_DIR\config.txt"
$LOG_FILE      = "$WORK_DIR\install.log"
$TASK_NAME     = "WinPC Control Server"

function Write-Step ([string]$msg) {
    Write-Host ""
    Write-Host "  >> $msg" -ForegroundColor Cyan
}

function Write-OK ([string]$msg) {
    Write-Host "     OK: $msg" -ForegroundColor Green
}

function Write-Fail ([string]$msg) {
    Write-Host "     FAIL: $msg" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor White
Write-Host "  WinPC Control  —  Windows Setup" -ForegroundColor White
Write-Host "================================================" -ForegroundColor White
Write-Host "  Port:  $Port"
Write-Host "  User:  $env:USERNAME"
Write-Host ""


# ---- Step 1: Create working directory ----
Write-Step "Creating working directory $WORK_DIR"
try {
    New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null
    Write-OK "$WORK_DIR ready"
}
catch {
    Write-Fail "Could not create $WORK_DIR : $_"
}


# ---- Step 2: Copy server script ----
Write-Step "Copying server script"
$source = Join-Path $PSScriptRoot $SERVER_SCRIPT
if (-not (Test-Path $source)) {
    Write-Fail "$SERVER_SCRIPT not found next to install.ps1. Make sure both files are in the same folder."
}
try {
    Copy-Item -Path $source -Destination "$WORK_DIR\$SERVER_SCRIPT" -Force
    Write-OK "Copied $SERVER_SCRIPT → $WORK_DIR"
}
catch {
    Write-Fail "Could not copy script: $_"
}


# ---- Step 3: Generate auth token and write config ----
Write-Step "Generating auth token"
try {
    $tokenBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $token = [System.Convert]::ToBase64String($tokenBytes)

    $configContent = "PORT=$Port`r`nTOKEN=$token`r`n"
    Set-Content -Path $CONFIG_FILE -Value $configContent -NoNewline
    Write-OK "Token generated and saved to $CONFIG_FILE"
}
catch {
    Write-Fail "Could not generate token: $_"
}


# ---- Step 4: Register HTTP URL ACL (allows non-admin to bind port) ----
Write-Step "Registering HTTP URL reservation for port $Port"
try {
    # Remove any existing reservation for this port first
    $null = & netsh http delete urlacl url="http://+:$Port/" 2>&1

    $result = & netsh http add urlacl url="http://+:$Port/" user=Everyone
    if ($LASTEXITCODE -eq 0) {
        Write-OK "URL ACL registered for http://+:$Port/"
    }
    else {
        Write-Fail "netsh urlacl failed: $result"
    }
}
catch {
    Write-Fail "Could not register URL ACL: $_"
}


# ---- Step 5: Add Windows Firewall rule ----
Write-Step "Adding Windows Firewall inbound rule (TCP port $Port)"
try {
    # Remove existing rule with same name first
    Remove-NetFirewallRule -DisplayName "WinPC Control HTTP" -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "WinPC Control HTTP" `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   $Port `
        -Action      Allow `
        -Profile     Any `
        -Description "Allows Q-SYS plugin to reach WinPCControlServer on port $Port" | Out-Null

    Write-OK "Firewall rule added (TCP $Port inbound, all profiles)"
}
catch {
    Write-Fail "Could not add firewall rule: $_"
}


# ---- Step 6: Create Scheduled Task ----
Write-Step "Creating Scheduled Task '$TASK_NAME' (runs at logon of $env:USERNAME)"
try {
    # Remove any existing task
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue

    $psExe    = "powershell.exe"
    $taskArgs = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WORK_DIR\$SERVER_SCRIPT`""

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings  = New-ScheduledTaskSettingsSet `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero)   # No timeout — runs forever

    # Interactive logon type ensures audio API access (runs in user session)
    $principal = New-ScheduledTaskPrincipal `
                    -UserId   "$env:USERDOMAIN\$env:USERNAME" `
                    -LogonType Interactive `
                    -RunLevel  Limited   # Non-elevated — audio requires this

    Register-ScheduledTask `
        -TaskName  $TASK_NAME `
        -Action    $action `
        -Trigger   $trigger `
        -Settings  $settings `
        -Principal $principal `
        -Force | Out-Null

    Write-OK "Scheduled Task '$TASK_NAME' created"
}
catch {
    Write-Fail "Could not create Scheduled Task: $_"
}


# ---- Step 7: Log install and display token ----
$installRecord = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installed by $env:USERNAME on $env:COMPUTERNAME (port $Port)"
Add-Content -Path $LOG_FILE -Value $installRecord

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  WinPC Control — Installation complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Copy this token into the Q-SYS plugin properties:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  $token" -ForegroundColor White
Write-Host ""
Write-Host "  The server will start automatically the next time" -ForegroundColor Gray
Write-Host "  $env:USERNAME logs into this PC." -ForegroundColor Gray
Write-Host ""
Write-Host "  To start it now without logging out/in, run:" -ForegroundColor Gray
Write-Host "  Start-ScheduledTask -TaskName '$TASK_NAME'" -ForegroundColor Gray
Write-Host ""
