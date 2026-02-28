<#
.SYNOPSIS
    Generates a Vagrant test environment for a PSADT package.

.PARAMETER PackagePath
    Absolute path to the PSADT package directory.

.PARAMETER AppName
    Application display name (used for validation checks).

.PARAMETER AppVendor
    Application vendor name.

.PARAMETER OutputPath
    Where to create the test environment. Defaults to a 'test' subfolder inside the package.

.PARAMETER CheckFiles
    Array of file paths to verify exist after install.

.PARAMETER CheckRegistry
    Array of hashtables with Key, Name, Expected for registry validation.

.PARAMETER CheckShortcutRemoved
    Path to a shortcut that should NOT exist after install.

.EXAMPLE
    .\generate_test.ps1 -PackagePath "C:\Desktop\GoogleChrome" -AppName "Google Chrome" -AppVendor "Google"
#>

param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [Parameter(Mandatory)]
    [string]$AppName,

    [string]$AppVendor = '',

    [string]$OutputPath = '',

    [string[]]$CheckFiles = @(),

    [hashtable[]]$CheckRegistry = @(),

    [string]$CheckShortcutRemoved = ''
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$PackagePath = (Resolve-Path $PackagePath).Path
if (-not $OutputPath) {
    $OutputPath = Join-Path $PackagePath 'test'
}

$skillDir = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $skillDir 'assets\Vagrantfile.template'

# Create test directory structure
$resultsDir = Join-Path $OutputPath 'results'
$scriptsDir = Join-Path $OutputPath 'scripts'
New-Item -ItemType Directory -Path $OutputPath, $resultsDir, $scriptsDir -Force | Out-Null

# Generate VM name from app
$vmName = "psadt-test-$($AppName -replace '[^a-zA-Z0-9]', '-' -replace '-+', '-')".ToLower().TrimEnd('-')
if ($vmName.Length -gt 40) { $vmName = $vmName.Substring(0, 40) }

# Generate Vagrantfile from template
$vagrantfile = Get-Content $templatePath -Raw
$vagrantfile = $vagrantfile -replace '__PACKAGE_PATH__', ($PackagePath -replace '\\', '/')
$vagrantfile = $vagrantfile -replace '__RESULTS_PATH__', ($resultsDir -replace '\\', '/')
$vagrantfile = $vagrantfile -replace '__VM_NAME__', $vmName
Set-Content -Path (Join-Path $OutputPath 'Vagrantfile') -Value $vagrantfile -Encoding UTF8

# Generate validate.ps1
$validateChecks = @()

# App installed check
$validateChecks += @"
# Check application is installed
`$app = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                         "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { `$_.DisplayName -like "*$AppName*" }
`$checks += @{ Check = 'AppInstalled'; Pass = (`$null -ne `$app); Detail = if (`$app) { `$app.DisplayName } else { 'Not found' } }
"@

# File checks
foreach ($f in $CheckFiles) {
    $validateChecks += @"
`$checks += @{ Check = 'FileExists'; Pass = (Test-Path '$f'); Detail = '$f' }
"@
}

# Registry checks
foreach ($r in $CheckRegistry) {
    $validateChecks += @"
`$val = Get-ItemPropertyValue -Path '$($r.Key)' -Name '$($r.Name)' -ErrorAction SilentlyContinue
`$checks += @{ Check = 'Registry:$($r.Key)\$($r.Name)'; Pass = (`$val -eq '$($r.Expected)'); Detail = "Expected: $($r.Expected), Got: `$val" }
"@
}

# Shortcut removed check
if ($CheckShortcutRemoved) {
    $validateChecks += @"
`$checks += @{ Check = 'ShortcutRemoved'; Pass = (-not (Test-Path '$CheckShortcutRemoved')); Detail = '$CheckShortcutRemoved' }
"@
}

$validateScript = @"
`$checks = @()

$($validateChecks -join "`n`n")

# Summary
`$failed = `$checks | Where-Object { -not `$_.Pass }
`$result = @{
    AppName    = '$AppName'
    TotalChecks = `$checks.Count
    Passed     = (`$checks | Where-Object { `$_.Pass }).Count
    Failed     = `$failed.Count
    AllPassed  = `$failed.Count -eq 0
    Checks     = `$checks
    Timestamp  = (Get-Date -Format o)
}
`$result | ConvertTo-Json -Depth 3 | Set-Content "C:\vagrant_results\validation_result.json" -Encoding UTF8

# Console output
foreach (`$c in `$checks) {
    `$status = if (`$c.Pass) { 'PASS' } else { 'FAIL' }
    Write-Host "[`$status] `$(`$c.Check) - `$(`$c.Detail)"
}
if (`$result.AllPassed) {
    Write-Host "`nAll `$(`$checks.Count) checks passed." -ForegroundColor Green
} else {
    Write-Host "`n`$(`$failed.Count) of `$(`$checks.Count) checks failed." -ForegroundColor Red
    exit 1
}
"@
Set-Content -Path (Join-Path $scriptsDir 'validate.ps1') -Value $validateScript -Encoding UTF8

Write-Host "Test environment created at: $OutputPath"
Write-Host ""
Write-Host "Commands:"
Write-Host "  cd `"$OutputPath`""
Write-Host "  vagrant up                                    # Start VM + install"
Write-Host "  vagrant provision --provision-with validate   # Run validation"
Write-Host "  vagrant provision --provision-with uninstall  # Test uninstall"
Write-Host "  vagrant destroy -f                            # Tear down"
