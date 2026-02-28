# Vagrant PSADT Test Runner

Test PSADT deployment packages in an isolated Hyper-V VM using Vagrant. The VM is disposable — every test starts from a clean Windows image and is destroyed after validation.

## When to Use This Skill

- Testing a PSADT package (install, uninstall, repair) in a sandbox
- Validating silent install switches and exit codes
- Checking post-install state (registry keys, files, shortcuts, services)
- Verifying uninstall fully removes an application
- Smoke testing before staging to Intune/SCCM

## Prerequisites

1. **Hyper-V** enabled (Windows 11 Pro)
2. **Vagrant** installed: `winget install Hashicorp.Vagrant`
3. A **Windows Vagrant box** added (one-time setup):
   ```
   vagrant box add gusztavvargadr/windows-11 --provider hyperv
   ```

To check prerequisites:
```bash
vagrant --version
vagrant box list
```

## Workflow

### Step 1: Set Up Test Environment

Create a test directory alongside the PSADT package (or in a temp location):

```
PackageTest/
├── Vagrantfile          # Generated from template
├── scripts/
│   ├── install.ps1      # Runs install inside VM
│   ├── validate.ps1     # Checks install succeeded
│   └── uninstall.ps1    # Runs uninstall inside VM
└── results/             # Validation results written here
```

Generate the Vagrantfile using the template in this skill's `assets/` directory. Customize:
- `PACKAGE_PATH` — absolute path to the PSADT package folder
- `APP_NAME` — application display name (for validation)
- `APP_VENDOR` — vendor name (for validation)
- Validation checks (registry keys, file paths, shortcuts to verify)

### Step 2: Run the Test

```bash
# From the test directory:
vagrant up                    # Spin up clean Windows VM
vagrant provision             # Run install + validation (auto-runs on first 'up')

# Or run phases individually:
vagrant provision --provision-with install
vagrant provision --provision-with validate
vagrant provision --provision-with uninstall
```

### Step 3: Review Results

The validation provisioner writes results to the synced `results/` folder:
- `results/install_result.json` — exit code, log excerpts
- `results/validation_result.json` — pass/fail for each check

Read these files to determine test outcome.

### Step 4: Tear Down

```bash
vagrant destroy -f            # Delete the VM completely
```

### Full Test Cycle (single command)

```bash
vagrant up && vagrant provision --provision-with validate && vagrant destroy -f
```

## Generating Test Scripts

When generating test scripts for a specific PSADT package, populate the templates based on the package's `$adtSession` variables:

### install.ps1 (runs inside VM)

```powershell
# Run PSADT silent install
$packageDir = "C:\vagrant_package"
Push-Location $packageDir
& powershell.exe -ExecutionPolicy Bypass -File "Invoke-AppDeployToolkit.ps1" -DeployMode Silent
$exitCode = $LASTEXITCODE
Pop-Location

# Write result
@{ ExitCode = $exitCode; Timestamp = (Get-Date -Format o) } | ConvertTo-Json | Set-Content "C:\vagrant_results\install_result.json"
exit $exitCode
```

### validate.ps1 (runs inside VM)

```powershell
$checks = @()

# Check application is installed
$app = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                         "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*APP_NAME*" }
$checks += @{ Check = 'AppInstalled'; Pass = ($null -ne $app); Detail = $app.DisplayName }

# Check files exist
$filesToCheck = @(
    # Populate with expected install paths
    # "C:\Program Files\Vendor\App\app.exe"
)
foreach ($f in $filesToCheck) {
    $checks += @{ Check = "FileExists:$f"; Pass = (Test-Path $f); Detail = $f }
}

# Check registry keys
$regChecks = @(
    # @{ Key = 'HKLM:\SOFTWARE\...'; Name = 'ValueName'; Expected = 'value' }
)
foreach ($r in $regChecks) {
    $val = Get-ItemPropertyValue -Path $r.Key -Name $r.Name -ErrorAction SilentlyContinue
    $checks += @{ Check = "Registry:$($r.Key)\$($r.Name)"; Pass = ($val -eq $r.Expected); Detail = "Got: $val" }
}

# Check desktop shortcut removed (if applicable)
$shortcutPath = "C:\Users\Public\Desktop\APP_NAME.lnk"
$checks += @{ Check = 'ShortcutRemoved'; Pass = (-not (Test-Path $shortcutPath)); Detail = $shortcutPath }

# Write results
@{ Checks = $checks; AllPassed = ($checks | Where-Object { -not $_.Pass }).Count -eq 0 } |
    ConvertTo-Json -Depth 3 | Set-Content "C:\vagrant_results\validation_result.json"
```

### uninstall.ps1 (runs inside VM)

```powershell
$packageDir = "C:\vagrant_package"
Push-Location $packageDir
& powershell.exe -ExecutionPolicy Bypass -File "Invoke-AppDeployToolkit.ps1" -DeploymentType Uninstall -DeployMode Silent
$exitCode = $LASTEXITCODE
Pop-Location

@{ ExitCode = $exitCode; Timestamp = (Get-Date -Format o) } | ConvertTo-Json | Set-Content "C:\vagrant_results\uninstall_result.json"
exit $exitCode
```

## Vagrantfile Configuration

The Vagrantfile template is in `assets/Vagrantfile.template`. Key settings:

- **Box**: `gusztavvargadr/windows-11` (or `gusztavvargadr/windows-11-23h2-enterprise` for enterprise)
- **Provider**: Hyper-V with dynamic memory
- **Synced folders**:
  - PSADT package → `C:\vagrant_package` (read-only)
  - Results folder → `C:\vagrant_results`
- **Provisioners**: Named PowerShell provisioners for install, validate, uninstall

## Troubleshooting

- **"Vagrant box not found"**: Run `vagrant box add gusztavvargadr/windows-11 --provider hyperv`
- **SMB share prompt**: Vagrant synced folders on Hyper-V use SMB. Enter your Windows credentials when prompted, or use `type: "rsync"` in the Vagrantfile.
- **VM won't start**: Ensure Hyper-V is enabled and no other hypervisor (VirtualBox) is conflicting.
- **Slow first run**: The box download is ~6 GB. Subsequent runs reuse the cached box.
