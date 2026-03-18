[CmdletBinding()]
param(
    [switch]$RepairBrokenLoopbackWinHttpProxy,
    [switch]$ResetStoreCache,
    [switch]$OpenLogs
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
Write-Step 'Checking the configured Store source for a newer Codex version.'
$check = Get-CodexUpgradeCheck -IncludeInteractiveFlags -VerboseLogs -OpenLogs:$OpenLogs

if (-not [string]::IsNullOrWhiteSpace($check.Output)) {
    Write-Host $check.Output
}

if ($check.ExitCode -ne 0 -and $check.ExitCode -ne -1978335189) {
    throw ("winget upgrade failed with exit code {0}" -f $check.ExitCode)
}

$current = Get-InstalledCodexSnapshot
if ($null -eq $current) {
    throw 'OpenAI.Codex disappeared after the upgrade attempt.'
}

if ($current.Version -eq $installed.Version) {
    Write-Step ("Codex version is unchanged after the official Store update check: {0}" -f $current.Version)
}
else {
    Write-Step ("Codex updated successfully: {0} -> {1}" -f $installed.Version, $current.Version)
}
