@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo [*] 正在以管理员权限请求运行 setup.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~f0\setup.ps1\"' -Verb RunAs -Wait"
if errorlevel 1 (
    echo [!] 提权启动失败，尝试普通权限运行...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
)
endlocal
pause
