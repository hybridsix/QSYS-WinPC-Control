# ================================================================
# uninstall.ps1
# Removes all WinPC Control components from this PC.
# Run as Administrator.
#
# Removes: Scheduled Task, Firewall rule, URL ACL,
#          and C:\QSYS WinPC Control\
#
# Version: 0.1
# ================================================================

#Requires -RunAsAdministrator

param(
    [int]$Port = 2207
)

$WORK_DIR  = "C:\QSYS WinPC Control"
$TASK_NAME = "WinPC Control Server"

function Write-Step ([string]$msg) {
    Write-Host ""
    Write-Host "  >> $msg" -ForegroundColor Cyan
}

function Write-OK ([string]$msg) {
    Write-Host "     OK: $msg" -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================" -ForegroundColor White
Write-Host "  WinPC Control - Uninstall" -ForegroundColor White
Write-Host "================================================" -ForegroundColor White

# Read port from config if present (overrides param default)
$configFile = "$WORK_DIR\config.txt"
if (Test-Path $configFile) {
    $portLine = Get-Content $configFile | Where-Object { $_ -match "^PORT=\d+$" } | Select-Object -First 1
    if ($portLine -match "^PORT=(\d+)$") { $Port = [int]$Matches[1] }
}
Write-Host "  Port: $Port"
Write-Host ""


# ---- Stop and remove Scheduled Task ----
Write-Step "Removing Scheduled Task '$TASK_NAME'"
try {
    Stop-ScheduledTask  -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue
    Write-OK "Task removed"
}
catch {
    Write-Host "     WARN: $_" -ForegroundColor Yellow
}


# ---- Remove Firewall rule ----
Write-Step "Removing Firewall rule 'WinPC Control HTTP'"
try {
    Remove-NetFirewallRule -DisplayName "WinPC Control HTTP" -ErrorAction SilentlyContinue
    Write-OK "Firewall rule removed"
}
catch {
    Write-Host "     WARN: $_" -ForegroundColor Yellow
}


# ---- Remove URL ACL ----
Write-Step "Removing HTTP URL reservation for port $Port"
try {
    $null = & netsh http delete urlacl url="http://+:$Port/" 2>&1
    Write-OK "URL ACL removed"
}
catch {
    Write-Host "     WARN: $_" -ForegroundColor Yellow
}


# ---- Remove work directory ----
Write-Step "Removing $WORK_DIR"
try {
    if (Test-Path $WORK_DIR) {
        Remove-Item -Path $WORK_DIR -Recurse -Force
        Write-OK "$WORK_DIR removed"
    }
    else {
        Write-OK "$WORK_DIR not found - nothing to remove"
    }
}
catch {
    Write-Host "     WARN: Could not remove $WORK_DIR : $_" -ForegroundColor Yellow
}


Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Uninstall complete." -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
