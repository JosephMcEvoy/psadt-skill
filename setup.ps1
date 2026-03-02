#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates symlinks so Claude Code discovers skills and agents from this repo.

.DESCRIPTION
    Symlinks skills/ and agents/ into .claude/ where Claude Code looks for them.
    Idempotent — skips correct symlinks, fixes stale ones.

    On Windows, requires Developer Mode enabled (Settings > For developers) or
    an elevated prompt for New-Item -ItemType SymbolicLink.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

$claudeDir = Join-Path $repoRoot '.claude'
$claudeSkillsDir = Join-Path $claudeDir 'skills'
$claudeAgentsDir = Join-Path $claudeDir 'agents'

# Ensure .claude directories exist
foreach ($dir in @($claudeDir, $claudeSkillsDir, $claudeAgentsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function New-SymlinkIfNeeded {
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [switch]$IsFile
    )

    $itemType = if ($IsFile) { 'SymbolicLink' } else { 'SymbolicLink' }

    if (Test-Path $LinkPath) {
        $item = Get-Item $LinkPath -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            $currentTarget = $item.Target
            # Normalize for comparison
            $resolvedTarget = (Resolve-Path $TargetPath -ErrorAction SilentlyContinue).Path
            $resolvedCurrent = (Resolve-Path $currentTarget -ErrorAction SilentlyContinue).Path

            if ($resolvedCurrent -eq $resolvedTarget) {
                Write-Host "  [OK] $LinkPath -> $TargetPath (already correct)" -ForegroundColor Green
                return
            } else {
                Write-Host "  [..] Removing stale symlink: $LinkPath -> $currentTarget" -ForegroundColor Yellow
                Remove-Item $LinkPath -Force
            }
        } else {
            Write-Host "  [!!] $LinkPath exists but is not a symlink. Skipping." -ForegroundColor Red
            return
        }
    }

    try {
        New-Item -ItemType $itemType -Path $LinkPath -Target $TargetPath -Force | Out-Null
        Write-Host "  [OK] $LinkPath -> $TargetPath" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] Could not create symlink: $_" -ForegroundColor Red
        Write-Host "         On Windows, enable Developer Mode or run as Administrator." -ForegroundColor Yellow
    }
}

Write-Host "Setting up Claude Code symlinks..." -ForegroundColor Cyan
Write-Host ""

# --- Skills ---
Write-Host "Skills:" -ForegroundColor White
$skillsSource = Join-Path $repoRoot 'skills'
$skillDirs = Get-ChildItem -Path $skillsSource -Directory -ErrorAction SilentlyContinue

foreach ($skill in $skillDirs) {
    $linkPath = Join-Path $claudeSkillsDir $skill.Name
    $targetPath = Join-Path $skillsSource $skill.Name
    New-SymlinkIfNeeded -LinkPath $linkPath -TargetPath $targetPath
}

# --- Agents ---
Write-Host ""
Write-Host "Agents:" -ForegroundColor White
$agentsSource = Join-Path $repoRoot 'agents'
$agentFiles = Get-ChildItem -Path $agentsSource -File -Filter '*.md' -ErrorAction SilentlyContinue

foreach ($agent in $agentFiles) {
    $linkPath = Join-Path $claudeAgentsDir $agent.Name
    $targetPath = $agent.FullName
    New-SymlinkIfNeeded -LinkPath $linkPath -TargetPath $targetPath -IsFile
}

Write-Host ""
Write-Host "Done. Claude Code will now discover skills and agents from this repo." -ForegroundColor Cyan
