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

# Generate run_test.ps1 with Copy-VMFile approach (no SMB shares needed)
$escapedPackagePath = $PackagePath -replace "'", "''"
$runTestScript = @"
<#
.SYNOPSIS
    Runs PSADT package test in Vagrant VM with admin elevation.
    Uses Copy-VMFile to transfer files (no SMB shares needed).
    Output is written to results/test_log.txt for monitoring.
#>
param(
    [ValidateSet('full', 'install', 'validate', 'uninstall', 'destroy')]
    [string]`$Phase = 'full'
)

`$ErrorActionPreference = 'Continue'
`$testDir = `$PSScriptRoot
`$resultsDir = Join-Path `$testDir 'results'
`$logFile = Join-Path `$resultsDir 'test_log.txt'
`$vagrant = 'C:\Program Files\Vagrant\bin\vagrant.exe'

# --- Configuration ---
`$packagePath = '$escapedPackagePath'
`$vmName = '$vmName'

# Ensure results directory exists
New-Item -ItemType Directory -Path `$resultsDir -Force | Out-Null

# Check for admin and self-elevate if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to admin..."
    `$argList = "-ExecutionPolicy Bypass -File ```"`$PSCommandPath```" -Phase `$Phase"
    Start-Process powershell.exe -Verb RunAs -ArgumentList `$argList -Wait
    exit
}

Set-Location `$testDir

function Log(`$msg) {
    `$ts = Get-Date -Format 'HH:mm:ss'
    `$line = "[`$ts] `$msg"
    Write-Host `$line
    Add-Content -Path `$logFile -Value `$line
}

if (`$Phase -eq 'full') {
    Set-Content -Path `$logFile -Value "=== PSADT Test Run - `$(Get-Date -Format o) ===" -Encoding UTF8
}

function Ensure-HyperVSwitch {
    `$existingSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
    if (`$existingSwitches) {
        `$pick = `$existingSwitches | Where-Object { `$_.Name -eq 'Default Switch' } | Select-Object -First 1
        if (-not `$pick) { `$pick = `$existingSwitches | Where-Object { `$_.SwitchType -eq 'External' } | Select-Object -First 1 }
        if (-not `$pick) { `$pick = `$existingSwitches | Select-Object -First 1 }
        Log "Using Hyper-V switch: `$(`$pick.Name) (`$(`$pick.SwitchType))"
        return `$pick.Name
    }
    Log "ERROR: No Hyper-V virtual switches found. Please create one via Hyper-V Manager."
    exit 1
}

function Copy-PackageToVM {
    Log "Copying package files to VM..."
    `$vmPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
    `$vmCred = New-Object System.Management.Automation.PSCredential('vagrant', `$vmPassword)
    Invoke-Command -VMName `$vmName -Credential `$vmCred -ScriptBlock {
        New-Item -ItemType Directory -Path 'C:\vagrant_package' -Force | Out-Null
        New-Item -ItemType Directory -Path 'C:\vagrant_results' -Force | Out-Null
    }
    `$items = Get-ChildItem -Path `$packagePath -File
    foreach (`$item in `$items) {
        Copy-VMFile -Name `$vmName -SourcePath `$item.FullName -DestinationPath "C:\vagrant_package\`$(`$item.Name)" -FileSource Host -CreateFullPath -Force
    }
    Log "  Copied `$(`$items.Count) root files"
    `$dirs = Get-ChildItem -Path `$packagePath -Directory | Where-Object { `$_.Name -ne 'test' }
    foreach (`$dir in `$dirs) {
        `$dirFiles = Get-ChildItem -Path `$dir.FullName -Recurse -File
        foreach (`$f in `$dirFiles) {
            `$relativePath = `$f.FullName.Substring(`$packagePath.Length)
            Copy-VMFile -Name `$vmName -SourcePath `$f.FullName -DestinationPath "C:\vagrant_package`$relativePath" -FileSource Host -CreateFullPath -Force
        }
        Log "  Copied directory: `$(`$dir.Name) (`$(`$dirFiles.Count) files)"
    }
    Log "Package copy complete."
}

function Get-VMResult {
    param([string]`$ResultFile)
    try {
        `$vmPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
        `$vmCred = New-Object System.Management.Automation.PSCredential('vagrant', `$vmPassword)
        `$json = Invoke-Command -VMName `$vmName -Credential `$vmCred -ScriptBlock {
            param(`$path)
            if (Test-Path `$path) { Get-Content `$path -Raw } else { `$null }
        } -ArgumentList `$ResultFile
        if (`$json) {
            `$localName = Split-Path `$ResultFile -Leaf
            Set-Content -Path (Join-Path `$resultsDir `$localName) -Value `$json -Encoding UTF8
            return `$json | ConvertFrom-Json
        }
    } catch {
        Log "  Could not retrieve `$ResultFile : `$(`$_.Exception.Message)"
    }
    return `$null
}

try {
    if (`$Phase -in @('full', 'install')) {
        `$switchName = Ensure-HyperVSwitch
        `$vagrantfilePath = Join-Path `$testDir 'Vagrantfile'
        `$vfContent = Get-Content `$vagrantfilePath -Raw
        if (`$vfContent -match '__SWITCH_NAME__') {
            `$vfContent = `$vfContent -replace '__SWITCH_NAME__', `$switchName
            Set-Content -Path `$vagrantfilePath -Value `$vfContent -Encoding UTF8
            Log "Injected switch name '`$switchName' into Vagrantfile"
        }

        Log "PHASE: vagrant up (booting VM)"
        `$output = & `$vagrant up --provider hyperv --no-provision 2>&1 | Out-String
        Add-Content -Path `$logFile -Value `$output
        Log "vagrant up exit code: `$LASTEXITCODE"
        if (`$LASTEXITCODE -ne 0) { Log "ERROR: VM failed to start."; exit 1 }

        Log "Enabling Guest Service Interface..."
        Enable-VMIntegrationService -VMName `$vmName -Name 'Guest Service Interface' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5

        Copy-PackageToVM

        Log "PHASE: install"
        `$output = & `$vagrant provision --provision-with install 2>&1 | Out-String
        Add-Content -Path `$logFile -Value `$output
        Log "install exit code: `$LASTEXITCODE"
        `$installResult = Get-VMResult 'C:\vagrant_results\install_result.json'
        if (`$installResult) { Log "Install result: exit code `$(`$installResult.ExitCode)" }
        else { Log "WARNING: install_result.json not found in VM" }
    }

    if (`$Phase -in @('full', 'validate')) {
        Log "PHASE: validate"
        `$output = & `$vagrant provision --provision-with validate 2>&1 | Out-String
        Add-Content -Path `$logFile -Value `$output
        Log "validate exit code: `$LASTEXITCODE"
        `$valResult = Get-VMResult 'C:\vagrant_results\validation_result.json'
        if (`$valResult) {
            Log "Validation: `$(`$valResult.Passed)/`$(`$valResult.TotalChecks) passed, AllPassed=`$(`$valResult.AllPassed)"
            foreach (`$check in `$valResult.Checks) {
                `$status = if (`$check.Pass) { 'PASS' } else { 'FAIL' }
                Log "  [`$status] `$(`$check.Check) - `$(`$check.Detail)"
            }
        } else { Log "WARNING: validation_result.json not found in VM" }
    }

    if (`$Phase -in @('full', 'uninstall')) {
        Log "PHASE: uninstall"
        `$output = & `$vagrant provision --provision-with uninstall 2>&1 | Out-String
        Add-Content -Path `$logFile -Value `$output
        Log "uninstall exit code: `$LASTEXITCODE"
        `$unResult = Get-VMResult 'C:\vagrant_results\uninstall_result.json'
        if (`$unResult) { Log "Uninstall result: exit code `$(`$unResult.ExitCode)" }
        else { Log "WARNING: uninstall_result.json not found in VM" }
    }

    if (`$Phase -in @('full', 'destroy')) {
        Log "PHASE: destroy VM"
        `$output = & `$vagrant destroy -f 2>&1 | Out-String
        Add-Content -Path `$logFile -Value `$output
        Log "destroy exit code: `$LASTEXITCODE"
    }

    Log "=== Test run complete ==="
} catch {
    Log "ERROR: `$(`$_.Exception.Message)"
    Log "At: `$(`$_.InvocationInfo.ScriptLineNumber)"
}
"@
Set-Content -Path (Join-Path $OutputPath 'run_test.ps1') -Value $runTestScript -Encoding UTF8

Write-Host "Test environment created at: $OutputPath"
Write-Host ""
Write-Host "Commands:"
Write-Host "  cd `"$OutputPath`""
Write-Host "  powershell -ExecutionPolicy Bypass -File run_test.ps1              # Full test (auto-elevates)"
Write-Host "  powershell -ExecutionPolicy Bypass -File run_test.ps1 -Phase install   # Install only"
Write-Host "  powershell -ExecutionPolicy Bypass -File run_test.ps1 -Phase validate  # Validate only"
Write-Host "  powershell -ExecutionPolicy Bypass -File run_test.ps1 -Phase destroy   # Tear down"
