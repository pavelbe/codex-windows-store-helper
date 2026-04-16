[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$RemoveRoamingState,
    [switch]$OpenApp,
    [switch]$OpenLogs,
    [switch]$VerboseLogs,
    [string]$Market = 'US'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

function Get-ReinstallTargets {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $roamingAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    $packagesRoot = Join-Path $localAppData 'Packages'

    $packageDirs = @()
    if (Test-Path -LiteralPath $packagesRoot) {
        $packageDirs = @(Get-ChildItem -LiteralPath $packagesRoot -Force -ErrorAction SilentlyContinue | Where-Object Name -like 'OpenAI.Codex*')
    }

    [pscustomobject]@{
        PackageDataDirs = $packageDirs
        RoamingCodexDir = Join-Path $roamingAppData 'Codex'
    }
}

Assert-WingetAvailable

$installed = Get-InstalledCodexSnapshot
$latestOpenAiRelease = $null
try {
    $latestOpenAiRelease = Get-LatestOpenAiCodexAppRelease
}
catch {
    Write-Host ("OpenAI changelog lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$displayCatalogSummary = $null
try {
    $displayCatalogSummary = Get-DisplayCatalogSummary -Market $Market
}
catch {
    Write-Host ("Display catalog lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$targets = Get-ReinstallTargets

Write-Step ("Current Codex version: {0}" -f $(if ($null -ne $installed) { $installed.Version } else { 'not installed' }))
if ($null -ne $latestOpenAiRelease) {
    Write-Step ("Latest OpenAI Codex app release: {0} ({1})" -f $latestOpenAiRelease.Version, $latestOpenAiRelease.DateText)
}
if ($null -ne $displayCatalogSummary) {
    Write-Step ("Display catalog package for market {0}: {1}" -f $Market, $displayCatalogSummary.PackageVersion)
}

Write-Step 'Planned cleanup targets'
if ($targets.PackageDataDirs.Count -gt 0) {
    $targets.PackageDataDirs | Select-Object FullName, LastWriteTime | Format-Table -AutoSize
}
else {
    Write-Host 'No LocalAppData package data directories found for OpenAI.Codex.'
}
Write-Host ("Roaming Codex dir: {0}" -f $targets.RoamingCodexDir)
Write-Host ("Remove roaming state: {0}" -f $RemoveRoamingState)

if ($CheckOnly) {
    Write-Step 'Check-only verdict'
    Write-Host 'No package removal and no reinstall were executed.'
    return
}

Write-Step 'Stopping running Codex processes'
Get-Process Codex -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Step 'Removing current package'
if ($null -ne $installed) {
    Remove-AppxPackage -Package $installed.PackageFullName -ErrorAction Stop
    Write-Host ("Removed package: {0}" -f $installed.PackageFullName)
    Start-Sleep -Seconds 2
}
else {
    Write-Host 'Codex package was already absent.'
}

Write-Step 'Removing LocalAppData package state'
if ($targets.PackageDataDirs.Count -gt 0) {
    foreach ($dir in $targets.PackageDataDirs) {
        if (Test-Path -LiteralPath $dir.FullName) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
            Write-Host ("Removed: {0}" -f $dir.FullName)
        }
    }
}
else {
    Write-Host 'No LocalAppData package state to remove.'
}

Write-Step 'Removing roaming Codex state'
if ($RemoveRoamingState) {
    if (Test-Path -LiteralPath $targets.RoamingCodexDir) {
        Remove-Item -LiteralPath $targets.RoamingCodexDir -Recurse -Force -ErrorAction Stop
        Write-Host ("Removed roaming state: {0}" -f $targets.RoamingCodexDir)
    }
    else {
        Write-Host 'No roaming Codex directory to remove.'
    }
}
else {
    Write-Host 'Skipped by default. Pass -RemoveRoamingState if you want a deeper reset.'
}

Write-Step 'Reinstalling Codex from Microsoft Store'
$installArgs = @(
    'install',
    '--id', $script:CodexStoreId,
    '--source', 'msstore',
    '--accept-source-agreements',
    '--accept-package-agreements',
    '--authentication-mode', 'interactive'
)

if ($VerboseLogs) {
    $installArgs += '--verbose-logs'
}

if ($OpenLogs) {
    $installArgs += '--open-logs'
}

$install = Invoke-WingetWithCapture -Arguments $installArgs
if (-not [string]::IsNullOrWhiteSpace($install.Output)) {
    Write-Host $install.Output
}

if ($install.ExitCode -ne 0) {
    throw ("winget install failed with exit code {0}" -f $install.ExitCode)
}

$after = Get-InstalledCodexSnapshot
if ($null -eq $after) {
    throw 'Codex is still not installed after reinstall.'
}

Write-Step ("Codex version after reinstall: {0}" -f $after.Version)

if ($OpenApp) {
    Write-Step 'Launching Codex App'
    Start-Process 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
    Start-Sleep -Seconds 8
    Get-Process Codex -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime, MainWindowTitle | Format-Table -AutoSize
}

if ($null -eq $installed) {
    Write-Step ("Codex installed successfully: {0}" -f $after.Version)
}
else {
    Write-Step ("Codex reinstalled successfully: {0} -> {1}" -f $installed.Version, $after.Version)
}
