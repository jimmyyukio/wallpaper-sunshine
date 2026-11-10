@echo off
rem Restart SunshineService so a config change (global_prep_cmd) takes effect.
rem Needs elevation: this script re-launches itself as administrator via UAC.

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

echo Stopping SunshineService ...
sc stop SunshineService
timeout /t 4 >nul

echo Starting SunshineService ...
sc start SunshineService
timeout /t 3 >nul

sc query SunshineService | findstr /i "STATE"
echo.
echo Done. You can close this window.
pause
