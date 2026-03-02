# PSADT Packaging Pipeline

Enterprise application packaging, testing, and Intune deployment using PSAppDeployToolkit v4.

## Quick Start

1. Run `setup.ps1` to symlink skills and agents into `.claude/` for Claude Code discovery
2. Use the `intune-packager` agent to run the full pipeline, or invoke individual skills

## Skills

| Skill | Purpose | Key Prerequisites |
|-|-|-|
| `psadt` | Create PSADT deployment packages from MSI/EXE/MSIX installers | PSADT v4 toolkit (auto-downloaded by setup script) |
| `vagrant-test` | Test packages in an isolated Hyper-V VM | Hyper-V enabled, Vagrant installed, Windows 11 box |
| `intune-deploy` | Wrap as .intunewin and upload to Microsoft Intune | IntuneWin32App PS module, IntuneWinAppUtil.exe, Entra ID tenant |

## Agent

**intune-packager** — orchestrates the full pipeline with three stages:
1. **Package** (psadt) — create the PSADT package
2. **Test** (vagrant-test) — validate install/uninstall in a disposable VM
3. **Deploy** (intune-deploy) — wrap and upload to Intune

Each stage requires user approval before advancing. The agent stops on failure.

## Repo Structure

```
skills/          → Skill definitions (SKILL.md, assets, scripts, references)
agents/          → Agent definitions
setup.ps1        → Symlinks skills/agents into .claude/ for Claude Code
.claude/         → Claude Code discovery directory (populated by setup.ps1)
```

## Prerequisites by Stage

**Packaging (psadt):** No external dependencies — the setup script downloads PSADT v4 automatically.

**Testing (vagrant-test):**
- Windows 11 Pro with Hyper-V enabled
- Vagrant: `winget install Hashicorp.Vagrant`
- Windows box: `vagrant box add gusztavvargadr/windows-11 --provider hyperv`

**Deployment (intune-deploy):**
- IntuneWin32App module + IntuneWinAppUtil.exe (installed by `setup_intune_tools.ps1`)
- Entra ID tenant with DeviceManagementApps.ReadWrite.All permissions
