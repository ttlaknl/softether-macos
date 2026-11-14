# setup_core_win.ps1
# Windows PowerShell Compatibility Script (Pure ASCII to avoid GBK/UTF8 encoding issues)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows Environment: Fast Fetch SoftEther C Source Code" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$WorkingDir = (Get-Location).Path
$SourceZip = Join-Path $WorkingDir "softether_src.zip"
$ExtractDir = Join-Path $WorkingDir "softether_src"

if (Test-Path $ExtractDir) {
    Write-Host "[Status] Cleaning existing source directory at $ExtractDir..." -ForegroundColor Yellow
    Remove-Item -Path $ExtractDir -Recurse -Force
}

# 1. Clone source with submodules (GitHub ZIP does NOT include submodules - build will fail without them)
$GitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

if ($GitAvailable) {
    Write-Host "[Cloning] Using git clone --recursive (includes required submodules)..." -ForegroundColor Green
    try {
        git clone --depth 1 --recursive --shallow-submodules "https://github.com/SoftEtherVPN/SoftEtherVPN.git" $ExtractDir
        Write-Host "[Success] Source code cloned successfully with all submodules!" -ForegroundColor Green
    } catch {
        Write-Host "[Error] git clone failed: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[Warning] Git not found! Falling back to ZIP download." -ForegroundColor Yellow
    Write-Host "[Warning] ZIP packages do NOT include Git submodules - you may need to manually init submodules later." -ForegroundColor Yellow

    $Url1 = "https://github.com/SoftEtherVPN/SoftEtherVPN/archive/refs/heads/master.zip"
    $SourceZip = Join-Path $WorkingDir "softether_src.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url1 -OutFile $SourceZip -TimeoutSec 60
        Write-Host "[Success] Downloaded successfully via GitHub!" -ForegroundColor Green
    } catch {
        Write-Host "[Error] Download failed. Please install Git (winget install Git.Git) and retry." -ForegroundColor Red
        exit 1
    }

    # 2. Extract Archive
    Write-Host "[Extracting] Extracting source package to softether_src..." -ForegroundColor Green
    Expand-Archive -Path $SourceZip -DestinationPath $WorkingDir -Force

    $UnzippedDir = Get-ChildItem -Path $WorkingDir -Filter "SoftEtherVPN-*" | Select-Object -First 1
    if ($UnzippedDir) {
        Rename-Item -Path $UnzippedDir.FullName -NewName "softether_src"
    }

    if (Test-Path $SourceZip) {
        Remove-Item -Path $SourceZip -Force
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] Source code extracted successfully!" -ForegroundColor Green
Write-Host " Location: $ExtractDir" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
