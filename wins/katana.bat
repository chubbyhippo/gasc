@echo off
kanata.exe --cfg "%USERPROFILE%\kanata.kbd" --check
if errorlevel 1 (
    echo kanata.kbd failed --check; kanata NOT started. Fix the config and rerun.
    pause
    exit /b 1
)
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -WindowStyle Hidden -FilePath 'kanata.exe' -ArgumentList '--cfg','%USERPROFILE%\kanata.kbd'"
