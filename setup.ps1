#Requires -Version 5.1
<#
    setup.ps1 - 安装 Windows 本地运行所需的全部依赖。

    前置条件：已自行安装 Python 3.10+ 与 Node.js 20.19+ / 22.12+。
    本脚本会：创建 venv -> 安装 pip 依赖 -> 安装 Playwright Chromium -> 构建前端。
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    Write-Host ">>> $Exe $($Arguments -join ' ')"
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "命令失败 (exit $LASTEXITCODE): $Exe $($Arguments -join ' ')"
    }
}

# ---------- 1. 定位 Python ----------
$pythonExe = $null
$pythonPrefixArgs = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
    $probe = & py -3 --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pythonExe = 'py'
        $pythonPrefixArgs = @('-3')
        $versionText = ($probe | Out-String).Trim()
    }
}
if (-not $pythonExe -and (Get-Command python -ErrorAction SilentlyContinue)) {
    $probe = & python --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pythonExe = 'python'
        $versionText = ($probe | Out-String).Trim()
    }
}
if (-not $pythonExe) {
    throw '未找到可用的 Python。请先安装 Python 3.10+（https://www.python.org/downloads/），安装时勾选 Add Python to PATH。'
}

$versionMatch = [regex]::Match($versionText, '(\d+)\.(\d+)')
if (-not $versionMatch.Success) {
    throw "无法解析 Python 版本: $versionText"
}
$major = [int]$versionMatch.Groups[1].Value
$minor = [int]$versionMatch.Groups[2].Value
if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) {
    throw "Python 版本过低: $versionText（需要 >= 3.10）"
}
Write-Host "[+] 使用 Python: $versionText ($pythonExe)"

# ---------- 2. 创建 venv 并安装 Python 依赖 ----------
Invoke-Checked -Exe $pythonExe -Arguments ($pythonPrefixArgs + @('-m', 'venv', 'venv'))

$venvPython = Join-Path $repoRoot 'venv\Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    throw "虚拟环境创建失败：找不到 $venvPython"
}

Invoke-Checked -Exe $venvPython -Arguments @('-m', 'pip', 'install', '--upgrade', 'pip')
Invoke-Checked -Exe $venvPython -Arguments @('-m', 'pip', 'install', '-r', 'requirements.txt')
# python -m playwright 等价于 playwright CLI，无需把 venv\Scripts 加进 PATH
Invoke-Checked -Exe $venvPython -Arguments @('-m', 'playwright', 'install', 'chromium')

# ---------- 3. 检查 Node.js 并构建前端 ----------
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw '未找到 Node.js。请安装 Node.js 20.19+ 或 22.12+（https://nodejs.org/）。'
}
$nodeVersion = (& node --version).Trim()
$nodeMatch = [regex]::Match($nodeVersion, 'v?(\d+)\.(\d+)')
if (-not $nodeMatch.Success) {
    throw "无法解析 Node.js 版本: $nodeVersion"
}
$nodeMajor = [int]$nodeMatch.Groups[1].Value
$nodeMinor = [int]$nodeMatch.Groups[2].Value
$nodeOk = ($nodeMajor -eq 20 -and $nodeMinor -ge 19) -or ($nodeMajor -eq 22 -and $nodeMinor -ge 12) -or ($nodeMajor -gt 22)
if (-not $nodeOk) {
    throw "Node.js 版本不满足 Vite 7 要求: $nodeVersion（需要 20.19+ 或 22.12+）"
}
Write-Host "[+] 使用 Node.js: $nodeVersion"

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw '未找到 npm，请重新安装 Node.js 并勾选 npm。'
}

Push-Location (Join-Path $repoRoot 'frontend')
try {
    & npm ci
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[!] npm ci 失败，尝试使用 npmmirror 镜像重试...'
        & npm ci --registry=https://registry.npmmirror.com
        if ($LASTEXITCODE -ne 0) { throw 'npm ci 失败' }
    }
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw '前端构建失败 (npm run build)' }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host '[+] 安装完成！现在可以：'
Write-Host '    双击 start.bat 启动服务（或运行 .\start.ps1）'
Write-Host '    首次使用请打开 http://127.0.0.1:8000/panel 登录（导入 Cookie 或扫码）。'
