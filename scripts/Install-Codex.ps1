[CmdletBinding()]
param(
    [ValidateSet('Direct', 'Store')][string]$Source = 'Direct',
    [switch]$CheckOnly,
    [switch]$DownloadOnly,
    [string]$PackagePath,
    [switch]$OpenApp,
    [switch]$RepairBrokenLoopbackWinHttpProxy,
    [switch]$ResetStoreCache,
    [switch]$OpenLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Source -eq 'Direct') {
    if ($RepairBrokenLoopbackWinHttpProxy -or $ResetStoreCache) { throw 'Proxy/cache repair is separate. Use -Source Store explicitly for the legacy Store path.' }
    if ($OpenLogs) { Write-Warning 'Direct MSIX errors print AppX diagnostics; Store logs are not used.' }
    & (Join-Path $PSScriptRoot 'Install-CodexDirect.ps1') -CheckOnly:$CheckOnly -DownloadOnly:$DownloadOnly -PackagePath $PackagePath -OpenApp:$OpenApp
    return
}
if ($CheckOnly -or $DownloadOnly -or $PackagePath -or $OpenApp) { throw 'These options require -Source Direct. Use Get-CodexAppDoctor.ps1 for Store diagnostics.' }

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

Assert-WingetAvailable

if ($RepairBrokenLoopbackWinHttpProxy -or $ResetStoreCache) {
    & (Join-Path $PSScriptRoot 'Repair-StoreNetwork.ps1') `
        -ResetBrokenLoopbackWinHttpProxy:$RepairBrokenLoopbackWinHttpProxy `
        -ResetStoreCache:$ResetStoreCache
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
