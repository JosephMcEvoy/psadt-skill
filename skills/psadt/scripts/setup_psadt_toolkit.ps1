<#
.SYNOPSIS
    Downloads and sets up the PSADT v4 toolkit for a new package.

.DESCRIPTION
    Creates the PSADT package directory structure and either downloads the
    latest PSADT v4 release from GitHub or copies from an existing toolkit path.

.PARAMETER OutputPath
    Directory where the package structure will be created.

.PARAMETER ToolkitPath
    Optional path to an existing PSADT toolkit directory to copy from
    instead of downloading.

.EXAMPLE
    .\setup_psadt_toolkit.ps1 -OutputPath "C:\Packages\MyApp"

.EXAMPLE
    .\setup_psadt_toolkit.ps1 -OutputPath "C:\Packages\MyApp" -ToolkitPath "C:\PSADT\Toolkit"
#>

param(
    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string]$ToolkitPath
)

$ErrorActionPreference = 'Stop'

# Create package directory structure
$dirs = @('Files', 'SupportFiles', 'Assets')
foreach ($dir in $dirs) {
    $path = Join-Path $OutputPath $dir
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        Write-Host "  Created: $dir/"
    }
}

if ($ToolkitPath -and (Test-Path $ToolkitPath)) {
    Write-Host "Copying PSADT toolkit from: $ToolkitPath"

    # Copy core module
    $src = Join-Path $ToolkitPath 'PSAppDeployToolkit'
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $OutputPath -Recurse -Force
        Write-Host "  Copied: PSAppDeployToolkit/"
    }

    # Copy extensions if present
    $ext = Join-Path $ToolkitPath 'PSAppDeployToolkit.Extensions'
    if (Test-Path $ext) {
        Copy-Item -Path $ext -Destination $OutputPath -Recurse -Force
        Write-Host "  Copied: PSAppDeployToolkit.Extensions/"
    }

    # Copy launcher exe
    $exe = Join-Path $ToolkitPath 'Invoke-AppDeployToolkit.exe'
    if (Test-Path $exe) {
        Copy-Item -Path $exe -Destination $OutputPath -Force
        Write-Host "  Copied: Invoke-AppDeployToolkit.exe"
    }
}
else {
    Write-Host "Downloading latest PSADT v4 release from GitHub..."

    $apiUrl = 'https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/latest'
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PSADT-Skill' }

    # Find the v4 template zip asset
    $asset = $release.assets | Where-Object { $_.name -match 'Template_v4.*\.zip$' } | Select-Object -First 1
    if (-not $asset) {
        # Fallback to any toolkit zip
        $asset = $release.assets | Where-Object { $_.name -match 'PSAppDeployToolkit.*\.zip$' } | Select-Object -First 1
    }

    if (-not $asset) {
        Write-Error "Could not find PSADT toolkit zip in release $($release.tag_name). Available assets: $($release.assets.name -join ', ')"
        exit 1
    }

    $zipPath = Join-Path $env:TEMP "psadt-$($release.tag_name).zip"
    $extractPath = Join-Path $env:TEMP "psadt-extract-$($release.tag_name)"

    Write-Host "  Release: $($release.tag_name)"
    Write-Host "  Asset: $($asset.name)"
    Write-Host "  Downloading..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

    Write-Host "  Extracting..."
    if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Find the Toolkit directory in extracted content
    $toolkitDir = Get-ChildItem -Path $extractPath -Directory -Recurse |
        Where-Object { $_.Name -eq 'Toolkit' } | Select-Object -First 1

    if (-not $toolkitDir) {
        # Look for directory containing PSAppDeployToolkit module
        $toolkitDir = Get-ChildItem -Path $extractPath -Directory -Recurse |
            Where-Object { (Get-ChildItem -Path $_.FullName -Filter 'PSAppDeployToolkit' -Directory) } |
            Select-Object -First 1
    }

    if (-not $toolkitDir) {
        # Last resort: just use the extract root
        $toolkitDir = Get-Item $extractPath
    }

    # Copy toolkit files to output, skipping template script (we provide our own)
    Get-ChildItem -Path $toolkitDir.FullName | ForEach-Object {
        if ($_.Name -ne 'Invoke-AppDeployToolkit.ps1') {
            Copy-Item -Path $_.FullName -Destination $OutputPath -Recurse -Force
            Write-Host "  Copied: $($_.Name)"
        }
    }

    # Cleanup temp files
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Cleaned up temp files."
}

Write-Host ""
Write-Host "PSADT package structure ready at: $OutputPath"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Place installer files in: $OutputPath\Files\"
Write-Host "  2. Customize Invoke-AppDeployToolkit.ps1"
Write-Host "  3. Test: powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent"
