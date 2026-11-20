#Requires -Version 5.1
<#
    stop.ps1 - 停止 start.ps1 启动的本地 Web 服务（等价于原 stop.sh）。
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $repoRoot '.server.pid'

if (-not (Test-Path $pidFile)) {
    Write-Host '未找到运行中的服务（.server.pid 不存在）。'
    exit 0
}
$pidText = (Get-Content $pidFile -Raw).Trim()
if ($pidText -notmatch '^\d+$') {
    Remove-Item $pidFile -Force
    Write-Host 'PID 文件内容无效，已清理。'
    exit 0
}
$procId = [int]$pidText
$proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
if (-not $proc) {
    Remove-Item $pidFile -Force
    Write-Host "进程 $procId 已不存在，已清理 PID 文件。"
    exit 0
}
Stop-Process -Id $procId -Force
Remove-Item $pidFile -Force
Write-Host "[+] 服务已停止 (PID $procId)"
