#Requires -Version 5.1
<#
    start.ps1 - 启动本地 Web 服务（等价于原 start.sh）。

    默认参数与 Docker 镜像一致：MODE=all, HEADLESS=true, 监听 127.0.0.1:8000。
    Windows 桌面环境下若想让采集器显示浏览器窗口，可传 -Headless:$false。
    启动后会打开浏览器访问 http://127.0.0.1:8000 。
#>
param(
    [ValidateSet('all', 'web', 'scraper')]
    [string]$Mode = 'all',
    [bool]$Headless = $true,
    [switch]$NoBrowser,
    [int]$Port = 8000
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

$venvPython = Join-Path $repoRoot 'venv\Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    throw '找不到 venv\Scripts\python.exe，请先运行 setup.bat / setup.ps1。'
}
if (-not (Test-Path (Join-Path $repoRoot 'frontend\dist\index.html'))) {
    throw '找不到 frontend\dist\index.html，请先运行 setup.bat / setup.ps1 构建前端。'
}

$pidFile = Join-Path $repoRoot '.server.pid'
if (Test-Path $pidFile) {
    $oldPid = (Get-Content $pidFile -Raw).Trim()
    if ($oldPid -match '^\d+$') {
        $proc = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
        if ($proc) {
            throw "服务已在运行 (PID $oldPid)，请先运行 stop.bat / stop.ps1。"
        }
    }
    Remove-Item $pidFile -Force
}

# MODE=scraper 且未配置定时：跑一次采集就退出（对齐 docker-entrypoint.sh）
if ($Mode -eq 'scraper' -and -not $env:SCRAPER_SCHEDULE) {
    Write-Host '[*] MODE=scraper 且未设置 SCRAPER_SCHEDULE，执行单次采集后退出...'
    & $venvPython -u extract.py --incremental
    if ($LASTEXITCODE -ne 0) { throw "采集失败 (exit $LASTEXITCODE)" }
    Write-Host '[+] 单次采集完成。'
    exit 0
}

# 初始化数据库（与 docker-entrypoint.sh 一致）
& $venvPython -c "from extractor.models import init_db; init_db()"
if ($LASTEXITCODE -ne 0) { throw '数据库初始化失败' }

# 设置环境变量（仅本进程生效，不污染用户系统）
$env:MODE = $Mode
if ($Headless) { $env:HEADLESS = 'true' } else { $env:HEADLESS = 'false' }
$env:PYTHONUNBUFFERED = '1'
if (-not $env:SCRAPER_INCREMENTAL) { $env:SCRAPER_INCREMENTAL = 'true' }

# 启动 uvicorn；用 -PassThru 拿到进程对象，等价 start.sh 的 nohup + pid 文件。
# uvicorn 日志默认写 stderr，因此只重定向 stderr 到 .server.log；
# 注意 Start-Process 不允许 stdout/stderr 指向同一文件，stdout 保持默认（丢弃）。
$logPath = Join-Path $repoRoot '.server.log'
$arguments = @('-m', 'uvicorn', 'backend.main:app', '--host', '127.0.0.1', '--port', "$Port")
$proc = Start-Process -FilePath $venvPython -ArgumentList $arguments -PassThru -RedirectStandardError $logPath -WindowStyle Hidden
Set-Content -Path $pidFile -Value $proc.Id -Encoding ASCII

Start-Sleep -Seconds 2
$proc.Refresh()
if ($proc.HasExited) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    $tail = Get-Content $logPath -Tail 20 -ErrorAction SilentlyContinue
    throw "服务启动失败，请查看 .server.log；末尾内容：`n$tail"
}

Write-Host "[+] 服务已启动 (PID $($proc.Id))"
Write-Host "    浏览器访问: http://127.0.0.1:$Port"
Write-Host "    控制面板:   http://127.0.0.1:$Port/panel"
Write-Host "    日志文件:   $logPath"
if (-not $NoBrowser) {
    Start-Process "http://127.0.0.1:$Port"
}
