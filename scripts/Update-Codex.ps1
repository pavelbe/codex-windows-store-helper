[CmdletBinding()]
param(
    [switch]$RepairBrokenLoopbackWinHttpProxy,
    [switch]$ResetStoreCache,
    [switch]$OpenLogs,
    [string]$Market = 'US'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

Assert-WingetAvailable

if ($RepairBrokenLoopbackWinHttpProxy -or $ResetStoreCache) {
    $repairArgs = @()
    if ($RepairBrokenLoopbackWinHttpProxy) {
        $repairArgs += '-ResetBrokenLoopbackWinHttpProxy'
    }
    if ($ResetStoreCache) {
        $repairArgs += '-ResetStoreCache'
    }

    & (Join-Path $PSScriptRoot 'Repair-StoreNetwork.ps1') @repairArgs
}

$installed = Get-InstalledCodexSnapshot
if ($null -eq $installed) {
    Write-Step 'Codex is not installed; falling back to install.'
    & (Join-Path $PSScriptRoot 'Install-Codex.ps1') -OpenLogs:$OpenLogs
    return
}

Write-Step ("Current Codex version: {0}" -f $installed.Version)
$latestOpenAiRelease = $null
try {
    $latestOpenAiRelease = Get-LatestOpenAiCodexAppRelease
    Write-Step ("Latest OpenAI Codex app release: {0} ({1})" -f $latestOpenAiRelease.Version, $latestOpenAiRelease.DateText)
}
catch {
    Write-Host ("OpenAI changelog lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$displayCatalogSummary = $null
try {
    $displayCatalogSummary = Get-DisplayCatalogSummary -Market $Market
    Write-Step ("Display catalog package for market {0}: {1}" -f $Market, $displayCatalogSummary.PackageVersion)
}
catch {
    Write-Host ("Display catalog lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

Write-Step 'Checking the configured Store source for a newer Codex version.'
$check = Get-CodexUpgradeCheck -IncludeInteractiveFlags -VerboseLogs -OpenLogs:$OpenLogs

if (-not [string]::IsNullOrWhiteSpace($check.Output)) {
    Write-Host $check.Output
}

if ($check.ExitCode -ne 0 -and -not $check.NoUpdates) {
    throw ("winget upgrade failed with exit code {0}" -f $check.ExitCode)
}

$current = Get-InstalledCodexSnapshot
if ($null -eq $current) {
    throw 'OpenAI.Codex disappeared after the upgrade attempt.'
}

$installedTrain = Get-ReleaseTrain -VersionText $current.Version
$latestTrain = if ($null -ne $latestOpenAiRelease) { Get-ReleaseTrain -VersionText $latestOpenAiRelease.Version } else { $null }
$compareLatest = Compare-ReleaseTrain -Left $installedTrain -Right $latestTrain
$availablePackageCompare = if ($null -ne $displayCatalogSummary) { ([version]$current.Version).CompareTo([version]$displayCatalogSummary.PackageVersion) } else { $null }
$forceFallbackAttempted = $false

# Healthy OFFICE-PC path: msstore install --force can succeed even when
# winget upgrade still returns the standard "no updates" result.
if ($check.NoUpdates) {
    $hasNewerOfficialSignal = (
        ($null -ne $compareLatest -and $compareLatest -lt 0) -or
        ($null -ne $availablePackageCompare -and $availablePackageCompare -lt 0)
    )

    if ($hasNewerOfficialSignal) {
        $forceFallbackAttempted = $true
        Write-Step 'No update from winget upgrade, but newer official metadata exists. Trying winget install --force.'
        $forceArgs = @(
            'install',
            '--id', $script:CodexStoreId,
            '--source', 'msstore',
            '--force',
            '--accept-source-agreements',
            '--accept-package-agreements',
            '--authentication-mode', 'interactive',
            '--verbose-logs'
        )

        if ($OpenLogs) {
            $forceArgs += '--open-logs'
        }

        $forceResult = Invoke-WingetWithCapture -Arguments $forceArgs
        if (-not [string]::IsNullOrWhiteSpace($forceResult.Output)) {
            Write-Host $forceResult.Output
        }

        if ($forceResult.ExitCode -ne 0 -and -not $forceResult.NoUpdates) {
            throw ("winget install --force fallback failed with exit code {0}" -f $forceResult.ExitCode)
        }

        $current = Get-InstalledCodexSnapshot
        if ($null -eq $current) {
            throw 'OpenAI.Codex disappeared after the force-install fallback.'
        }
    }
}

if ($forceFallbackAttempted -and $current.Version -ne $installed.Version) {
    Write-Step ("Codex updated successfully via winget install --force fallback: {0} -> {1}" -f $installed.Version, $current.Version)
}
elseif ($current.Version -eq $installed.Version) {
    Write-Step ("Codex version is unchanged after the official Store update check: {0}" -f $current.Version)
}
else {
    Write-Step ("Codex updated successfully: {0} -> {1}" -f $installed.Version, $current.Version)
}
