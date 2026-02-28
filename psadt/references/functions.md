# PSADT v4 Function Reference

## Installation UI

### Show-ADTInstallationWelcome

Welcome dialog with process closure prompt and optional deferral.

```powershell
# Basic - close processes with countdown
Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 600

# With deferrals
Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -AllowDeferCloseProcesses -DeferTimes 3 -PersistPrompt

# Splatting pattern (recommended)
$saiwParams = @{
    AllowDeferCloseProcesses = $true
    DeferTimes = 3
    PersistPrompt = $true
}
if ($adtSession.AppProcessesToClose.Count -gt 0) {
    $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
}
Show-ADTInstallationWelcome @saiwParams
```

Key parameters: `-CloseProcesses`, `-CloseProcessesCountdown`, `-AllowDefer`, `-AllowDeferCloseProcesses`, `-DeferTimes`, `-PersistPrompt`, `-CheckDiskSpace`

### Show-ADTInstallationProgress

Progress dialog during installation.

```powershell
Show-ADTInstallationProgress
Show-ADTInstallationProgress -StatusMessage 'Installing application...'
```

### Show-ADTInstallationRestartPrompt

Prompt for restart after installation.

```powershell
Show-ADTInstallationRestartPrompt -CountdownSeconds 600 -CountdownNoHideSeconds 60
```

### Show-ADTInstallationPrompt

Custom dialog with message and buttons.

```powershell
Show-ADTInstallationPrompt -Message 'Installation complete.' -ButtonRightText 'OK' -Icon Information -NoWait
```

### Show-ADTDialogBox / Show-ADTBalloonTip

Simple notifications.

```powershell
Show-ADTDialogBox -Text 'Message' -Icon Information
Show-ADTBalloonTip -BalloonTipText 'Notification' -BalloonTipTitle 'Title'
```

## Installer Execution

### Start-ADTMsiProcess

Execute MSI operations.

```powershell
# Install MSI
Start-ADTMsiProcess -Action Install -FilePath 'installer.msi'

# Install with transform
Start-ADTMsiProcess -Action Install -FilePath 'installer.msi' -Transforms 'custom.mst'

# Install with additional parameters
Start-ADTMsiProcess -Action Install -FilePath 'installer.msi' -AddParameters 'PROPERTY=VALUE'

# Uninstall by MSI file
Start-ADTMsiProcess -Action Uninstall -FilePath 'installer.msi'

# Uninstall by product GUID
Start-ADTMsiProcess -Action Uninstall -FilePath '{12345678-1234-1234-1234-123456789012}'

# Apply patch
Start-ADTMsiProcess -Action Patch -FilePath 'patch.msp'
```

Key parameters: `-Action` (Install/Uninstall/Patch/Repair), `-FilePath`, `-Transforms`, `-AddParameters`, `-LoggingOptions`

### Start-ADTProcess

Execute any process.

```powershell
# EXE with silent switches
Start-ADTProcess -FilePath 'setup.exe' -ArgumentList '/S /v/qn'

# From Files directory
Start-ADTProcess -FilePath "$($adtSession.DirFiles)\setup.exe" -ArgumentList '/S'

# Wait for competing MSI
Start-ADTProcess -FilePath 'setup.exe' -ArgumentList '/S' -WaitForMsiExec

# Ignore specific exit codes
Start-ADTProcess -FilePath 'setup.exe' -ArgumentList '/S' -IgnoreExitCodes '1,2'

# Don't wait for process to complete
Start-ADTProcess -FilePath 'setup.exe' -ArgumentList '/S' -NoWait
```

Key parameters: `-FilePath`, `-ArgumentList`, `-WaitForMsiExec`, `-IgnoreExitCodes`, `-SecureArgumentList`, `-NoWait`

## Application Discovery & Removal

### Get-ADTApplication

Query installed applications from the registry.

```powershell
$app = Get-ADTApplication -Name 'Application Name'
$app = Get-ADTApplication -Name 'Application Name' -Exact
$app = Get-ADTApplication -ProductCode '{12345678-1234-1234-1234-123456789012}'
```

Returns objects with: DisplayName, DisplayVersion, ProductCode, UninstallString, InstallLocation, Publisher

### Uninstall-ADTApplication

Uninstall applications by name.

```powershell
Uninstall-ADTApplication -Name 'Application Name'
Uninstall-ADTApplication -Name 'Application Name' -NameMatch 'Exact'
Uninstall-ADTApplication -Name 'Application Name' -ArgumentList '/S'
Uninstall-ADTApplication -Name 'Application Name' -AddParameters 'REBOOT=Suppress'
```

## File Operations

### Copy-ADTFile

```powershell
Copy-ADTFile -Path "$($adtSession.DirFiles)\config.xml" -Destination "$env:ProgramData\App\"
Copy-ADTFile -Path "$($adtSession.DirSupportFiles)\*" -Destination "$env:ProgramFiles\App\" -Recurse
```

### Copy-ADTFileToUserProfiles

```powershell
Copy-ADTFileToUserProfiles -Path "$($adtSession.DirSupportFiles)\settings" -Destination 'AppData\Roaming\App' -Recurse
```

### Remove-ADTFile

```powershell
Remove-ADTFile -Path "$env:Public\Desktop\App.lnk"
Remove-ADTFile -Path "$envCommonDesktop\App.lnk", "$envCommonStartMenuPrograms\Vendor\Website.lnk"
```

### Remove-ADTFolder

```powershell
Remove-ADTFolder -Path "$env:ProgramData\App"
```

## Registry Operations

### Set-ADTRegistryKey

```powershell
Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'Setting' -Value '1' -Type 'String'
Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'Disabled' -Value 1 -Type 'DWord'
Set-ADTRegistryKey -Key 'HKLM\SOFTWARE\App'  # Create key only
```

### Remove-ADTRegistryKey

```powershell
Remove-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'Setting'  # Remove value
Remove-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Recurse  # Remove entire key
```

### Get-ADTRegistryKey

```powershell
$value = Get-ADTRegistryKey -Key 'HKLM\SOFTWARE\App' -Name 'Setting'
```

## Shortcuts

### New-ADTShortcut

```powershell
New-ADTShortcut -Path "$envCommonDesktop\App.lnk" -TargetPath "$env:ProgramFiles\App\app.exe"
New-ADTShortcut -Path "$envCommonStartMenuPrograms\App.lnk" -TargetPath "$env:ProgramFiles\App\app.exe" -IconLocation "$env:ProgramFiles\App\app.ico"
```

## Active Setup

### Set-ADTActiveSetup

Per-user actions on login (useful for HKCU changes in machine-context installs).

```powershell
Set-ADTActiveSetup -StubExePath "$env:ProgramFiles\App\configure.exe" -Description 'App Config' -Key 'AppConfig'
Set-ADTActiveSetup -PurgeActiveSetupKey -Key 'AppConfig'  # Remove Active Setup
```

## Services

```powershell
Set-ADTServiceStartMode -Name 'ServiceName' -StartMode 'Automatic'
Stop-ADTServiceAndDependencies -Name 'ServiceName'
Start-ADTServiceAndDependencies -Name 'ServiceName'
```

## Session Variables

Key variables available via `$adtSession` inside deployment functions:

| Variable | Description |
|-|-|
| `$adtSession.DirFiles` | Path to `Files/` directory |
| `$adtSession.DirSupportFiles` | Path to `SupportFiles/` directory |
| `$adtSession.DirAppDeployTemp` | Temp directory for the deployment |
| `$adtSession.ScriptDirectory` | Script root directory |
| `$adtSession.DeploymentType` | Current type: Install/Uninstall/Repair |
| `$adtSession.DeployMode` | Current mode: Interactive/Silent/NonInteractive/Auto |
| `$adtSession.UseDefaultMsi` | True if Zero-Config MSI mode is active |
| `$adtSession.DefaultMsiFile` | Auto-detected MSI file path |
| `$adtSession.DefaultMstFile` | Auto-detected MST transform path |
| `$adtSession.DefaultMspFiles` | Auto-detected MSP patch files |

## Environment Variables

PSADT provides shorthand variables for common paths:

| Variable | Path |
|-|-|
| `$envCommonDesktop` | C:\Users\Public\Desktop |
| `$envCommonStartMenuPrograms` | C:\ProgramData\Microsoft\Windows\Start Menu\Programs |
| `$envCommonStartMenu` | C:\ProgramData\Microsoft\Windows\Start Menu |
| `$envProgramFiles` | C:\Program Files |
| `$envProgramFilesX86` | C:\Program Files (x86) |
| `$envProgramData` | C:\ProgramData |
| `$envWinDir` | C:\Windows |
| `$envSystemDrive` | C:\ |
| `$envTemp` | User temp directory |

## Common Silent Install Switches

Reference for common installer types:

| Installer Type | Silent Install | Silent Uninstall |
|-|-|-|
| MSI | `msiexec /i file.msi /qn` | `msiexec /x file.msi /qn` |
| InstallShield | `/s /v"/qn"` | `/s /v"/qn"` |
| NSIS | `/S` | `/S` |
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| WiX Burn | `/quiet /norestart` | `/quiet /norestart /uninstall` |

For unknown EXEs, check: `setup.exe /?`, `setup.exe /help`, or consult vendor documentation.
