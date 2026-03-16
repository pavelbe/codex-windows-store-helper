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

$installed = Get-InstalledCodexPackage
if ($null -eq $installed) {
    Write-Step 'Codex is not installed; falling back to install.'
    & (Join-Path $PSScriptRoot 'Install-Codex.ps1') -OpenLogs:$OpenLogs
    return
}

Write-Step ("Current Codex version: {0}" -f $installed.Version)

$args = @(
    'upgrade',
    '--id', $script:CodexStoreId,
    '--source', 'msstore',
    '--accept-source-agreements',
    '--accept-package-agreements',
    '--authentication-mode', 'interactive',
    '--verbose-logs'
)

if ($OpenLogs) {
    $args += '--open-logs'
}

$output = (& winget @args 2>&1)
$output | Out-Host

$exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
$noUpdateExitCode = -1978335189

if ($exitCode -ne 0) {
    if ($exitCode -ne $noUpdateExitCode) {
        throw ("winget upgrade failed with exit code {0}" -f $exitCode)
    }

    Write-Step 'No newer Codex version is available in the configured Store source.'
}

$current = Get-InstalledCodexPackage
if ($null -eq $current) {
    throw 'OpenAI.Codex disappeared after the upgrade attempt.'
}

Write-Step ("Codex is present after update check: {0}" -f $current.Version)
