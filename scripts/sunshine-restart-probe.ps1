$ErrorActionPreference = "Continue"
$log = "C:\Tools\wallpaper-sunshine\logs\sunshine-restart.log"

function Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content -LiteralPath $log -Value $line -Encoding ASCII
    Write-Output $line
}

Log "=== restart requested ==="
Stop-Service -Name SunshineService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Start-Service -Name SunshineService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 14

$svc = Get-Service SunshineService -ErrorAction SilentlyContinue
Log ("service=" + $svc.Status)

$procs = @(Get-Process Sunshine -ErrorAction SilentlyContinue)
Log ("sunshine_processes=" + $procs.Count)

$ports = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in 47984, 47989, 47990 })
Log ("listening_ports=" + (($ports | ForEach-Object { $_.LocalPort } | Sort-Object) -join ","))

$errs = @(Get-WinEvent -FilterHashtable @{ LogName='Application'; Id=1000; StartTime=(Get-Date).AddMinutes(-2) } -ErrorAction SilentlyContinue)
Log ("recent_app_errors=" + $errs.Count)

if ($ports.Count -eq 0) {
    Log "RESULT=FAILED_NO_LISTENER"
} else {
    Log "RESULT=OK"
}
