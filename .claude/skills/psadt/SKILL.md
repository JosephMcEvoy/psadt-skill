---
name: psadt
description: Package applications with PSAppDeployToolkit (PSADT) v4. This skill should be used when the user wants to create a PSADT deployment package, wrap an installer (MSI, EXE, MSIX) with PSADT, generate an Invoke-AppDeployToolkit.ps1 script, or needs help with PSADT deployment functions and patterns.
---

# PSADT Application Packager

Create enterprise deployment packages using PSAppDeployToolkit v4.x. PSADT wraps installers (MSI, EXE, MSIX) with a standardized framework providing UI prompts, logging, process management, and error handling.

## When to Use This Skill

- Packaging an application with PSADT
- Creating or editing an `Invoke-AppDeployToolkit.ps1` deployment script
- Setting up PSADT package folder structure
- Wrapping MSI, EXE, or MSIX installers with PSADT
- Adding pre/post-install actions (registry, file copy, shortcuts, Active Setup)
- Writing uninstall or repair logic for a PSADT package

## Workflow

### Step 1: Gather Information

Present the user with three input modes and proceed based on their choice:

**Mode A — Installer files provided**: The user has installer files (MSI/EXE/etc.) and provides paths. Ask for:
- Application name, vendor, version, architecture
- Silent install/uninstall command-line switches
- Processes that must be closed before install
- Any post-install tasks (shortcuts to remove, registry keys, config files)

**Mode B — Installer files + instructions**: The user provides both files and deployment instructions (silent switches, registry changes, etc.). Extract the details and confirm before proceeding.

**Mode C — Application name only**: The user names an application but has no installer files or instructions. Research the application's:
- Installer type (MSI, EXE, MSIX)
- Silent install switches (check vendor docs or common patterns)
- Uninstall method (product GUID, uninstall string, or EXE)
- Processes to close

For any mode, the minimum required information before proceeding:
1. **AppName** and **AppVendor**
2. **Installer file name** and type (MSI/EXE/MSIX)
3. **Silent install switches**
4. **Uninstall method**

### Step 2: Set Up Package Structure

A PSADT v4 package has this folder structure:

```
PackageName/
├── Invoke-AppDeployToolkit.ps1    # Deployment script (generated)
├── Invoke-AppDeployToolkit.exe    # Launcher (from PSADT toolkit)
├── PSAppDeployToolkit/            # Core module (from PSADT toolkit)
├── PSAppDeployToolkit.Extensions/ # Optional extensions
├── Files/                         # Installer files (MSI, EXE, etc.)
├── SupportFiles/                  # Auxiliary files (configs, transforms)
└── Assets/                        # Icons, banners (optional)
```

**To set up the toolkit**, check if PSADT toolkit files exist in the target directory. If not, offer the user two options:

1. **Auto-download**: Run the setup script to download the latest PSADT v4 release:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "<skill-scripts-dir>/setup_psadt_toolkit.ps1" -OutputPath "<package-dir>"
   ```

2. **Copy from existing**: If the user has PSADT toolkit files already:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "<skill-scripts-dir>/setup_psadt_toolkit.ps1" -OutputPath "<package-dir>" -ToolkitPath "<existing-toolkit-dir>"
   ```

Replace `<skill-scripts-dir>` with the absolute path to this skill's `scripts/` directory.

After the toolkit is set up, copy the user's installer files into the `Files/` directory.

### Step 3: Generate the Deployment Script

Read the template at `assets/Invoke-AppDeployToolkit.ps1` in this skill's directory. Customize it by:

1. **Populate `$adtSession` variables** with the gathered app information:
   - `AppVendor`, `AppName`, `AppVersion`, `AppArch`
   - `AppProcessesToClose` — array of `@{ Name = 'process'; Description = 'Display Name' }`
   - `AppScriptDate` — current date in `yyyy-MM-dd` format
   - `AppScriptAuthor` — user name or organization

2. **Fill in `Install-ADTDeployment`** based on installer type:

   **MSI installer:**
   ```powershell
   Start-ADTMsiProcess -Action Install -FilePath 'installer.msi'
   # With transform:
   Start-ADTMsiProcess -Action Install -FilePath 'installer.msi' -Transforms 'custom.mst'
   # With properties:
   Start-ADTMsiProcess -Action Install -FilePath 'installer.msi' -AddParameters 'PROPERTY=VALUE'
   ```

   **EXE installer:**
   ```powershell
   Start-ADTProcess -FilePath "$($adtSession.DirFiles)\setup.exe" -ArgumentList '/S /v/qn'
   ```

   **Zero-Config MSI** (leave `AppName` empty, put a single MSI in `Files/`):
   The template already handles this via `$adtSession.UseDefaultMsi`. No custom install commands needed.

3. **Fill in `Uninstall-ADTDeployment`** based on uninstall method:

   **By application name:**
   ```powershell
   Uninstall-ADTApplication -Name 'Application Name' -NameMatch 'Exact' -ArgumentList '/S'
   ```

   **By MSI product GUID:**
   ```powershell
   Start-ADTMsiProcess -Action Uninstall -FilePath '{PRODUCT-GUID}'
   ```

   **By MSI file:**
   ```powershell
   Start-ADTMsiProcess -Action Uninstall -FilePath 'installer.msi'
   ```

4. **Add post-install tasks** as needed:
   - Remove unwanted desktop shortcuts: `Remove-ADTFile -Path "$envCommonDesktop\App.lnk"`
   - Copy config files: `Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\config.xml" -Destination "$env:ProgramData\App\"`
   - Set registry keys: `Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'Setting' -Value '1' -Type 'String'`
   - Per-user config: `Copy-ADTFileToUserProfiles` or `Set-ADTActiveSetup`

5. **Fill in `Repair-ADTDeployment`** — typically combines uninstall + reinstall logic.

For the complete PSADT v4 function reference, read `references/functions.md` in this skill's directory.

### Step 4: Validate the Package

After generating the script, verify:

- [ ] `$adtSession` has all required fields populated (no empty AppName/AppVendor/AppVersion)
- [ ] Installer file names in the script match actual files in `Files/`
- [ ] Silent switches are correct for the installer type
- [ ] Uninstall logic is present and uses correct method
- [ ] `AppProcessesToClose` lists all relevant processes
- [ ] No hardcoded absolute paths (use `$adtSession.DirFiles`, `$adtSession.DirSupportFiles`, environment variables)
- [ ] Post-install cleanup (unwanted shortcuts, registry) is handled

### Step 5: Provide Testing Instructions

After creating the package, provide the user with test commands:

```powershell
# Interactive install (shows UI)
powershell.exe -File Invoke-AppDeployToolkit.ps1

# Silent install (no UI)
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

# Silent uninstall
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall -DeployMode Silent

# Using the EXE launcher (hides PowerShell window)
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

## Installer Type Patterns

### MSI Package

```powershell
# $adtSession
AppProcessesToClose = @(@{ Name = 'appprocess'; Description = 'App Name' })

# Install
Start-ADTMsiProcess -Action Install -FilePath 'app.msi'

# Uninstall
Start-ADTMsiProcess -Action Uninstall -FilePath 'app.msi'
```

### EXE Installer (NSIS)

```powershell
# Install
Start-ADTProcess -FilePath "$($adtSession.DirFiles)\setup.exe" -ArgumentList '/S'

# Uninstall
Uninstall-ADTApplication -Name 'Application Name' -ArgumentList '/S'
```

### EXE Installer (Inno Setup)

```powershell
# Install
Start-ADTProcess -FilePath "$($adtSession.DirFiles)\setup.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'

# Uninstall
Uninstall-ADTApplication -Name 'Application Name' -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
```

### EXE Installer (InstallShield)

```powershell
# Install
Start-ADTProcess -FilePath "$($adtSession.DirFiles)\setup.exe" -ArgumentList '/s /v"/qn"'

# Uninstall - typically via MSI product code
$app = Get-ADTApplication -Name 'Application Name'
if ($app) { Start-ADTMsiProcess -Action Uninstall -FilePath $app.ProductCode }
```

### MSI with Transform

```powershell
# Install
Start-ADTMsiProcess -Action Install -FilePath 'app.msi' -Transforms 'custom.mst'

# Uninstall
Start-ADTMsiProcess -Action Uninstall -FilePath 'app.msi'
```

### MSI with Patch

```powershell
# Install base + patch
Start-ADTMsiProcess -Action Install -FilePath 'app.msi'
Start-ADTMsiProcess -Action Patch -FilePath 'update.msp'
```

## Common Post-Install Patterns

### Remove Unwanted Shortcuts

```powershell
Remove-ADTFile -Path "$envCommonDesktop\App.lnk"
Remove-ADTFile -Path "$envCommonStartMenuPrograms\Vendor\Website.lnk", "$envCommonStartMenuPrograms\Vendor\Help.lnk"
```

### Deploy Configuration Files

```powershell
# Machine-level config
Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\config.xml" -Destination "$env:ProgramData\App\"

# Per-user config
Copy-ADTFileToUserProfiles -Path "$($adtSession.DirSupportFiles)\settings" -Destination 'AppData\Roaming\App' -Recurse
```

### Registry Customization

```powershell
# Disable auto-update
Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'AutoUpdate' -Value 0 -Type 'DWord'

# Disable telemetry
Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'UsageCollection' -Value 0 -Type 'DWord'
```

### Per-User Actions via Active Setup

For HKCU changes when deploying in SYSTEM context:

```powershell
# In Post-Install
Set-ADTActiveSetup -StubExePath 'powershell.exe' -Arguments '-NoProfile -Command "Set-ItemProperty -Path HKCU:\SOFTWARE\App -Name Setting -Value 1"' -Description 'Configure App' -Key 'AppUserConfig' -Version '1'

# In Post-Uninstall
Set-ADTActiveSetup -PurgeActiveSetupKey -Key 'AppUserConfig'
```

## Testing

Use the **vagrant-test** skill to test packages in an isolated Hyper-V VM before deploying to Intune/SCCM. The test workflow:

1. Spins up a clean Windows 11 VM via Vagrant
2. Maps the PSADT package folder into the VM
3. Runs silent install, validates the result (installed apps, registry, files, shortcuts)
4. Runs uninstall and verifies cleanup
5. Destroys the VM

See the `vagrant-test` skill for setup and usage.
