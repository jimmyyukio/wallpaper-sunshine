# we-prep.ps1 - conditional Wallpaper Engine toggle for Sunshine
#
# Called from Sunshine's global_prep_cmd. It only sends play/pause when Wallpaper
# Engine is already running; if WE is closed it exits immediately and never
# launches it.
#
# Why: `wallpaper64.exe -control play` with WE closed starts the whole application
# and stays resident (wallpaper64 plus several wallpaperui processes). Sunshine
# waits for prep commands synchronously with no timeout, so the stream launch
# would hang until the client times out. The guard keeps that from happening.
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this script> play
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this script> pause
#
# Always exits 0: the wallpaper toggle is a nicety, it must never fail a stream.

param(
    [Parameter(Mandatory = $true)][ValidateSet('play', 'pause', 'open', 'close', 'stop')][string]$Action,
    [string]$Exe = 'C:\wl\wallpaper64.exe',
    [string]$LogFile = '',
    [int]$TimeoutSec = 5
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $LogFile) {
    $LogFile = Join-Path $PSScriptRoot 'logs\we-prep.log'
}

function Write-Log([string]$msg) {
    try {
        $dir = Split-Path -Parent $LogFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $LogFile -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
    } catch { }
}

if (-not (Test-Path $Exe)) {
    Write-Log "skip ($Action): exe missing: $Exe"
    exit 0
}

$we = @(Get-Process -Name wallpaper64, wallpaper32 -ErrorAction SilentlyContinue)
if ($we.Count -eq 0) {
    Write-Log "skip ($Action): wallpaper engine not running"
    exit 0
}

$proc = Start-Process -FilePath $Exe -ArgumentList '-control', $Action -PassThru -WindowStyle Hidden
if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    try { $proc.Kill() } catch { }
    Write-Log "timeout ($Action): killed after ${TimeoutSec}s"
    exit 0
}

Write-Log "sent ($Action): we_pid=$($we[0].Id) exit=$($proc.ExitCode)"
exit 0
