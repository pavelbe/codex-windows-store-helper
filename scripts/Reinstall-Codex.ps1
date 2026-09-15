[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$DownloadOnly,
    [string]$PackagePath,
    [switch]$OpenApp,
    [switch]$RemoveRoamingState,
    [switch]$OpenLogs,
    [switch]$VerboseLogs,
    [string]$Market
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($RemoveRoamingState) {
    throw 'Automatic data deletion is no longer supported. Reinstallation preserves app data; diagnose a state reset separately.'
}
if ($OpenLogs -or $VerboseLogs -or $Market) {
    Write-Warning 'Store log/market options do not apply to direct MSIX installation. Deployment errors print AppX diagnostics.'
}
& (Join-Path $PSScriptRoot 'Install-CodexDirect.ps1') -CheckOnly:$CheckOnly -DownloadOnly:$DownloadOnly -PackagePath $PackagePath -OpenApp:$OpenApp
