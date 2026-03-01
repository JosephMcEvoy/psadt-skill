# Vagrant PSADT Test Runner

Test PSADT deployment packages in an isolated Hyper-V VM using Vagrant. The VM is disposable — every test starts from a clean Windows image and is destroyed after validation.

## When to Use This Skill

- Testing a PSADT package (install, uninstall, repair) in a sandbox
- Validating silent install switches and exit codes
- Checking post-install state (registry keys, files, shortcuts, services)
- Verifying uninstall fully removes an application
- Smoke testing before staging to Intune/SCCM

## Prerequisites

1. **Hyper-V** enabled (Windows 11 Pro) with a virtual switch (the "Default Switch" is created automatically)
2. **Vagrant** installed: `winget install Hashicorp.Vagrant`
3. A **Windows Vagrant box** added (one-time ~6 GB download):
   ```
   "C:\Program Files\Vagrant\bin\vagrant.exe" box add gusztavvargadr/windows-11 --provider hyperv
   ```

Note: Vagrant may not be in Git Bash PATH after install. Use full path: `"C:\Program Files\Vagrant\bin\vagrant.exe"`

## How It Works

The test runner uses **Copy-VMFile** (Hyper-V's built-in file transfer) instead of SMB shared folders. This avoids credential prompts and network share issues entirely.

Flow:
1. `vagrant up --no-provision` — boots a clean Windows 11 VM
2. Enables Guest Service Interface on the VM (required for Copy-VMFile)
3. Copies the PSADT package into the VM via `Copy-VMFile`
4. Runs install/validate/uninstall provisioners via `vagrant provision`
5. Pulls result JSON from the VM via `Invoke-Command -VMName`
6. `vagrant destroy -f` — deletes the VM

## Workflow

### Step 1: Generate Test Environment

Use `generate_test.ps1` to scaffold a test directory for any PSADT package:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "<skill-scripts-dir>/generate_test.ps1" `
    -PackagePath "C:\path\to\PSADTPackage" `
    -AppName "Application Name" `
    -AppVendor "Vendor" `
    -CheckFiles @("C:\Program Files\App\app.exe") `
    -CheckShortcutRemoved "C:\Users\Public\Desktop\App.lnk"
```

This creates:

```
PSADTPackage/test/
├── Vagrantfile          # VM configuration (no synced folders)
├── run_test.ps1         # Self-elevating test runner
├── scripts/
│   └── validate.ps1     # App-specific validation checks
└── results/             # Test results (JSON + log)
```

### Step 2: Run the Test

```powershell
# Full cycle: boot → copy files → install → validate → uninstall → destroy
powershell.exe -ExecutionPolicy Bypass -File run_test.ps1

# Or run individual phases:
powershell.exe -ExecutionPolicy Bypass -File run_test.ps1 -Phase install
powershell.exe -ExecutionPolicy Bypass -File run_test.ps1 -Phase validate
powershell.exe -ExecutionPolicy Bypass -File run_test.ps1 -Phase uninstall
powershell.exe -ExecutionPolicy Bypass -File run_test.ps1 -Phase destroy
```

The script auto-elevates to admin (required for Hyper-V). Monitor progress in `results/test_log.txt`.

### Step 3: Review Results

Results are written to the `results/` directory:
- `test_log.txt` — full run log with timestamps and PASS/FAIL per check
- `install_result.json` — install exit code and timing
- `validation_result.json` — detailed check results
- `uninstall_result.json` — uninstall exit code and timing

## Key Design Decisions

- **Copy-VMFile over SMB**: SMB synced folders require interactive credential prompts that break automation. Copy-VMFile transfers files directly through the Hyper-V bus with no network dependency.
- **Guest Service Interface**: Must be enabled on the VM after boot for Copy-VMFile to work. The test runner handles this automatically.
- **No `netcfg -d`**: Never use `netcfg -d` to troubleshoot networking. It resets all network drivers and can require a full Windows reinstall.
- **`--no-provision` on boot**: Separates VM startup from provisioning so files can be copied in between.
- **Self-elevating scripts**: Hyper-V operations require admin. Scripts detect and self-elevate via UAC prompt.

## Troubleshooting

- **"Vagrant not found"**: Use full path `"C:\Program Files\Vagrant\bin\vagrant.exe"` or restart terminal after install.
- **"No Hyper-V switches"**: Enable Hyper-V in Windows Features and reboot. The "Default Switch" is created automatically.
- **"Guest Service Interface" errors**: The test runner enables this automatically. If it still fails, check that Hyper-V Integration Services are installed in the VM.
- **VM boot timeout**: Increase `config.winrm.timeout` in Vagrantfile (default 600s).
- **Slow first run**: The box download is ~6 GB. Subsequent runs reuse the cached box.
