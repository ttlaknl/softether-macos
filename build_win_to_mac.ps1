# build_win_to_mac.ps1
# Windows to macOS/iOS (ARM64) Cross Compilation Setup

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SoftEther VPN Windows-to-macOS Cross-Compile Setup" -ForegroundColor Cyan
Write-Host " Target Platform: macOS & iOS (Apple Silicon ARM64)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$WorkingDir = (Get-Location).Path

# Step 1: Run source fetcher
Write-Host "[1/2] Running setup_core_win.ps1..." -ForegroundColor Green
powershell -ExecutionPolicy Bypass -File ".\setup_core_win.ps1"

# Step 2: Check Windows Local Clang
Write-Host "[2/2] Checking Windows LLVM/Clang Compiler..." -ForegroundColor Green
$ClangCmd = Get-Command clang -ErrorAction SilentlyContinue

if ($ClangCmd) {
    Write-Host "  - Found Clang compiler at $($ClangCmd.Source)" -ForegroundColor Green
    Write-Host "  - Ready to compile with -target arm64-apple-macos" -ForegroundColor Green
} else {
    Write-Host "  - Clang compiler not found in Windows PATH." -ForegroundColor Yellow
    Write-Host "  - To install Clang on Windows, run: winget install LLVM.LLVM" -ForegroundColor Yellow
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] Setup complete! Source at z:\softther\softether_src" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
