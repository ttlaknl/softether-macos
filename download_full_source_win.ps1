# download_full_source_win.ps1
# Windows 全量源码离线准备脚本 (支持在 Win 上下载完后在 macOS 上直接离线编译)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Fast Download SoftEther Source on Windows for macOS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$WorkingDir = (Get-Location).Path
$ExtractDir = Join-Path $WorkingDir "softether_src"

Write-Host "[1/2] Fetching full source repository with submodules on Windows..." -ForegroundColor Green

# 优先在 Windows 使用 Git 浅克隆 (速度极快且稳定)
$GitCmd = Get-Command git -ErrorAction SilentlyContinue

if ($GitCmd) {
    Write-Host "  - Found Git on Windows, running fast shallow clone..." -ForegroundColor Green
    if (Test-Path $ExtractDir) { Remove-Item -Path $ExtractDir -Recurse -Force }
    git clone --depth 1 --recursive --shallow-submodules https://github.com/SoftEtherVPN/SoftEtherVPN.git $ExtractDir
} else {
    Write-Host "  - Git not found on Windows. Running PowerShell setup_core_win.ps1..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File ".\setup_core_win.ps1"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] Full source code is ready in $ExtractDir" -ForegroundColor Green
Write-Host " Next step: Run 'make core' on macOS directly (No download needed!)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
