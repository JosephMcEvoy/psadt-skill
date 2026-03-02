---
name: intune-deploy
description: Deploy PSADT packages to Microsoft Intune as Win32 apps. This skill should be used when the user wants to upload a PSADT package to Intune, wrap it as an .intunewin file, create a Win32 app in Intune via Graph API, or configure detection rules, install commands, and group assignments.
---

# Intune Win32 App Deployer

Deploy PSADT packages to Microsoft Intune as Win32 apps using the IntuneWin32App PowerShell module and the Microsoft Win32 Content Prep Tool.

## When to Use This Skill

- Wrapping a PSADT package as `.intunewin` for Intune upload
- Creating a Win32 app in Intune from a PSADT package
- Configuring detection rules, install/uninstall commands, and requirements
- Uploading `.intunewin` content to Intune via Graph API
- Assigning an Intune Win32 app to an Entra ID group

## Prerequisites

1. **IntuneWin32App** PowerShell module — handles Graph API authentication and Win32 app management
2. **IntuneWinAppUtil.exe** (Microsoft Win32 Content Prep Tool) — packages folders into `.intunewin` format

Run the setup script to install both (idempotent):

```powershell
powershell.exe -ExecutionPolicy Bypass -File "<skill-scripts-dir>/setup_intune_tools.ps1"
```

Replace `<skill-scripts-dir>` with the absolute path to this skill's `scripts/` directory.

3. **Entra ID (Azure AD) tenant** — you need a Tenant ID with appropriate permissions (DeviceManagementApps.ReadWrite.All)

## Workflow

### Step 1: Wrap Package as .intunewin

Every PSADT package uses `Invoke-AppDeployToolkit.exe` as the setup file. Wrap it using the Content Prep Tool:

```powershell
IntuneWinAppUtil.exe -c "<package-dir>" -s "Invoke-AppDeployToolkit.exe" -o "<output-dir>" -q
```

- `-c` — source folder containing the PSADT package
- `-s` — setup file (always `Invoke-AppDeployToolkit.exe` for PSADT packages)
- `-o` — output directory for the `.intunewin` file
- `-q` — quiet mode (no prompts)

This produces `<output-dir>\Invoke-AppDeployToolkit.intunewin`.

### Step 2: Connect to Graph API

```powershell
Connect-MSIntuneGraph -TenantID "<tenant-id>"
```

This triggers a device code authentication flow. The user must open a browser, go to https://microsoft.com/devicelogin, and enter the code displayed in the console. The module handles token acquisition and refresh.

Ask the user for their Tenant ID before connecting.

### Step 3: Create Win32 App

Build the app configuration and upload:

```powershell
# Detection rule — file-based (most common for PSADT)
$DetectionRule = New-IntuneWin32AppDetectionRuleFile `
    -Existence `
    -Path "C:\Program Files\<vendor>\<app>" `
    -FileOrFolder "<app-executable>.exe" `
    -DetectionType "exists"

# Alternative: MSI product code detection
$DetectionRule = New-IntuneWin32AppDetectionRuleMSI `
    -ProductCode "{PRODUCT-GUID}" `
    -ProductVersionOperator "greaterThanOrEqual" `
    -ProductVersion "<version>"

# Alternative: registry detection
$DetectionRule = New-IntuneWin32AppDetectionRuleRegistry `
    -Existence `
    -KeyPath "HKLM\SOFTWARE\<vendor>\<app>" `
    -ValueName "Version" `
    -DetectionType "exists"

# Requirement rule
$RequirementRule = New-IntuneWin32AppRequirementRule `
    -Architecture "x64" `
    -MinimumSupportedWindowsRelease "W10_21H2"

# Create the app
$IntuneApp = Add-IntuneWin32App `
    -FilePath "<output-dir>\Invoke-AppDeployToolkit.intunewin" `
    -DisplayName "<AppVendor> <AppName> <AppVersion>" `
    -Description "Deployed via PSADT" `
    -Publisher "<AppVendor>" `
    -AppVersion "<AppVersion>" `
    -InstallCommandLine "Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent" `
    -UninstallCommandLine "Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent" `
    -InstallExperience "system" `
    -RestartBehavior "suppress" `
    -DetectionRule $DetectionRule `
    -RequirementRule $RequirementRule
```

**Important**: Install/uninstall commands are standardized for all PSADT packages:
- Install: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`
- Uninstall: `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`

### Step 4: Assign to Group (Optional)

```powershell
# Required assignment (auto-install)
Add-IntuneWin32AppAssignmentGroup `
    -ID $IntuneApp.id `
    -GroupID "<entra-group-id>" `
    -Intent "required" `
    -Notification "showAll"

# Available assignment (Company Portal)
Add-IntuneWin32AppAssignmentGroup `
    -ID $IntuneApp.id `
    -GroupID "<entra-group-id>" `
    -Intent "available" `
    -Notification "showAll"
```

Ask the user whether they want to assign the app and to which group.

### Step 5: Verify

After upload, confirm the app exists in Intune:

```powershell
Get-IntuneWin32App -DisplayName "<AppName>"
```

Present the user with:
- Intune App ID
- Display name
- Upload status
- Detection rule summary
- Assignment status (if assigned)

## Detection Rule Patterns

Choose the detection rule based on what the application installs:

| Scenario | Rule Type | Example |
|-|-|-|
| EXE app in Program Files | File existence | `C:\Program Files\App\app.exe` |
| MSI-based installer | MSI product code | `{GUID}` with version check |
| Registry key set by installer | Registry existence | `HKLM\SOFTWARE\Vendor\App` |
| Custom version check | Registry version | Registry value comparison |

For PSADT packages, file-based detection is the most reliable since you know exactly where the app installs.

## Troubleshooting

- **"IntuneWinAppUtil not found"**: Run `setup_intune_tools.ps1` or add its location to PATH.
- **"Connect-MSIntuneGraph fails"**: Ensure the IntuneWin32App module is installed (`Install-Module IntuneWin32App`). Check Tenant ID is correct.
- **"Insufficient privileges"**: The authenticating account needs DeviceManagementApps.ReadWrite.All permission in Entra ID.
- **"Content upload timeout"**: Large packages may take time. The module handles chunked upload automatically.
- **Detection rule mismatch**: After deploying, check the app installs to the expected path. Use `Get-IntuneWin32AppDetection` to verify.

## Pipeline Context

This skill is the final stage in the PSADT pipeline:
1. **psadt** skill — creates the PSADT deployment package
2. **vagrant-test** skill — tests install/uninstall in an isolated VM
3. **intune-deploy** skill (this) — wraps and uploads to Intune

Use the `intune-packager` agent to orchestrate all three stages with user checkpoints.
