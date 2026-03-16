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

$existing = Get-InstalledCodexPackage
if ($null -ne $existing) {
    Write-Step ("Codex is already installed: {0}" -f $existing.Version)
    Write-Host 'Nothing to do. Use Update-Codex.ps1 to check for a newer Store version.'
    return
}

$args = @(
    'install',
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

$exitCode = Invoke-WingetCommand -Arguments $args
if ($exitCode -ne 0) {
    throw ("winget install failed with exit code {0}" -f $exitCode)
}

$installed = Get-InstalledCodexPackage
if ($null -eq $installed) {
    throw 'winget reported success, but OpenAI.Codex is still not installed.'
}

Write-Step ("Codex installed successfully: {0}" -f $installed.Version)
