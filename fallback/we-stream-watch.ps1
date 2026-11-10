# Watch Sunshine's log and toggle Wallpaper Engine with the stream lifecycle.
# Runs in the user session (session 1), so it can reach the running WE instance.
# play  when a stream session starts;  pause  DEBOUNCE seconds after it ends.

$ErrorActionPreference = "Continue"

$LogPath   = "D:\Program Files\Sunshine\config\sunshine.log"
$WeExe     = "D:\Program Files\steam\steamapps\common\wallpaper_engine\wallpaper64.exe"
$StateFile = "C:\Tools\wallpaper-sunshine\logs\we-stream-watch.log"
$Debounce  = 12          # seconds to wait after a disconnect before pausing
$Poll      = 1           # seconds between log checks

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -LiteralPath $StateFile -Value $line -Encoding ASCII } catch {}
}

function Control-We([string]$mode) {
    if (-not (Test-Path $WeExe)) { Log "WE exe missing"; return }
    try {
        Start-Process -FilePath $WeExe -ArgumentList '-control', $mode -WindowStyle Hidden -ErrorAction Stop
        Log ("sent: " + $mode)
    } catch {
        Log ("send failed: " + $mode + " :: " + $_.Exception.Message)
    }
}

function LastEvent() {
    # Returns @{ kind = 'start'|'stop'|''; ts = [datetime] } for the newest marker in the log tail.
    $kind = ''
    $stamp = $null
    if (-not (Test-Path $LogPath)) { return @{ kind = ''; ts = $null } }
    try {
        $tail = Get-Content -LiteralPath $LogPath -Tail 300 -ErrorAction Stop
    } catch { return @{ kind = ''; ts = $null } }

    foreach ($line in $tail) {
        if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            $t = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
            if ($line -match 'New streaming session started' -or $line -match 'CLIENT CONNECTED') {
                if (-not $stamp -or $t -ge $stamp) { $kind = 'start'; $stamp = $t }
            } elseif ($line -match 'CLIENT DISCONNECTED' -or $line -match 'Stopping streaming session') {
                if (-not $stamp -or $t -gt $stamp) { $kind = 'stop'; $stamp = $t }
            }
        }
    }
    return @{ kind = $kind; ts = $stamp }
}

Log "=== watcher started ==="

# single instance guard: exit if another copy of this script is already running
$me = $PID
$others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*we-stream-watch.ps1*' })
if ($others.Count -gt 0) {
    Log ("another watcher already running (pid " + ($others | ForEach-Object { $_.ProcessId }) + ") -> exit")
    exit 0
}

$active = $false          # believed stream state
$lastHandled = $null      # last event timestamp we acted on
$pendingPause = $null     # [datetime] when to pause (after a stop)

while ($true) {
    $ev = LastEvent
    if ($ev.ts -and ($null -eq $lastHandled -or $ev.ts -gt $lastHandled)) {
        if ($ev.kind -eq 'start') {
            $lastHandled = $ev.ts
            $pendingPause = $null
            if (-not $active) {
                $active = $true
                Log ("stream STARTED (" + $ev.ts + ") -> play")
                Control-We 'play'
            }
        } elseif ($ev.kind -eq 'stop') {
            $lastHandled = $ev.ts
            if ($active) {
                $active = $false
                $pendingPause = (Get-Date).AddSeconds($Debounce)
                Log ("stream STOPPED (" + $ev.ts + ") -> pause in " + $Debounce + "s")
            }
        }
    }

    if ($pendingPause -and (Get-Date) -ge $pendingPause) {
        $pendingPause = $null
        # only pause if no newer start arrived meanwhile
        $ev2 = LastEvent
        if ($ev2.kind -ne 'start' -or $ev2.ts -lt $lastHandled) {
            Log "debounce elapsed -> pause"
            Control-We 'pause'
        }
    }

    Start-Sleep -Seconds $Poll
}
