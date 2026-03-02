#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Installs prerequisites for Intune Win32 app deployment.

.DESCRIPTION
    Downloads IntuneWinAppUtil.exe (Microsoft Win32 Content Prep Tool) and installs
    the IntuneWin32App PowerShell module. Idempotent — skips components already present.

.PARAMETER ToolsPath
    Directory to download IntuneWinAppUtil.exe into. Defaults to ~\.intunewin-tools.
#>

param(
    [string]$ToolsPath = (Join-Path $HOME '.intunewin-tools')
)

$ErrorActionPreference = 'Stop'

# --- IntuneWin32App PowerShell module ---
$moduleName = 'IntuneWin32App'
$installed = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue

if ($installed) {
    Write-Host "[OK] $moduleName module already installed (v$($installed.Version))" -ForegroundColor Green
} else {
    Write-Host "[..] Installing $moduleName module from PSGallery..." -ForegroundColor Yellow
    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
    $installed = Get-Module -ListAvailable -Name $moduleName
    Write-Host "[OK] $moduleName module installed (v$($installed.Version))" -ForegroundColor Green
}

# --- IntuneWinAppUtil.exe (Win32 Content Prep Tool) ---
$exeName = 'IntuneWinAppUtil.exe'
$exePath = Join-Path $ToolsPath $exeName

if (Test-Path $exePath) {
    Write-Host "[OK] $exeName already exists at $exePath" -ForegroundColor Green
} else {
    Write-Host "[..] Downloading $exeName from Microsoft GitHub..." -ForegroundColor Yellow

    if (-not (Test-Path $ToolsPath)) {
        New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
    }

    # Get latest release URL from Microsoft's GitHub repo
    $apiUrl = 'https://api.github.com/repos/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest'
    $headers = @{ 'User-Agent' = 'PowerShell' }
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

    # Find the .exe asset in the release
    $asset = $release.assets | Where-Object { $_.name -eq $exeName }

    if (-not $asset) {
        # Fallback: download the zipball and extract
        Write-Host "  Direct exe not found in release assets. Downloading zipball..." -ForegroundColor Yellow
        $zipPath = Join-Path $ToolsPath 'content-prep-tool.zip'
        $extractPath = Join-Path $ToolsPath '_extract'

        Invoke-WebRequest -Uri $release.zipball_url -OutFile $zipPath -Headers $headers
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $foundExe = Get-ChildItem -Path $extractPath -Recurse -Filter $exeName | Select-Object -First 1
        if ($foundExe) {
            Copy-Item -Path $foundExe.FullName -Destination $exePath -Force
        } else {
            throw "Could not find $exeName in the downloaded release."
        }

        # Cleanup
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $exePath -Headers $headers
    }

    Write-Host "[OK] $exeName downloaded to $exePath" -ForegroundColor Green
}

# --- Add tools directory to PATH for current session ---
if ($env:PATH -notlike "*$ToolsPath*") {
    $env:PATH = "$ToolsPath;$env:PATH"
    Write-Host "[OK] Added $ToolsPath to session PATH" -ForegroundColor Green
}

Write-Host ""
Write-Host "Setup complete. Tools available:" -ForegroundColor Cyan
Write-Host "  - IntuneWin32App module: Import-Module $moduleName"
Write-Host "  - Content Prep Tool:     $exePath"
Write-Host ""
Write-Host "To persist PATH, add to your PowerShell profile:" -ForegroundColor Yellow
Write-Host "  `$env:PATH = `"$ToolsPath;`$env:PATH`""
