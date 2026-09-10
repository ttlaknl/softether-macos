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

# 1. Download Sources using GitHub Mirror or Direct Zip
$Url1 = "https://ghproxy.net/https://github.com/SoftEtherVPN/SoftEtherVPN/archive/refs/heads/master.zip"
$Url2 = "https://github.com/SoftEtherVPN/SoftEtherVPN/archive/refs/heads/master.zip"

$Downloaded = $false

Write-Host "[Downloading] Attempting fast mirror download from $Url1..." -ForegroundColor Green
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url1 -OutFile $SourceZip -TimeoutSec 45
    $Downloaded = $true
    Write-Host "[Success] Downloaded successfully via Mirror!" -ForegroundColor Green
} catch {
    Write-Host "[Warning] Mirror download failed or timed out. Trying direct GitHub link..." -ForegroundColor Yellow
}

if (-not $Downloaded) {
    try {
        Invoke-WebRequest -Uri $Url2 -OutFile $SourceZip -TimeoutSec 60
        $Downloaded = $true
        Write-Host "[Success] Downloaded successfully via GitHub!" -ForegroundColor Green
    } catch {
        Write-Host "[Error] Download failed. Please check network or download zip manually." -ForegroundColor Red
        exit 1
    }
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

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] Source code extracted successfully!" -ForegroundColor Green
Write-Host " Location: $ExtractDir" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
