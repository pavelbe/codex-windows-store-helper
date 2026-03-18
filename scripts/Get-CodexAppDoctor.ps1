[CmdletBinding()]
param(
    [int]$HistoryDays = 7,
    [int]$MaxHistoryEvents = 12,
    [string]$Market = 'US',
    [switch]$SkipStorePage,
    [switch]$SkipManifest,
    [switch]$SkipWingetCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

Assert-WingetAvailable

Write-Step 'Environment'
[pscustomobject]@{
    CurrentTimeLocal           = Get-Date
    StoreId                    = $script:CodexStoreId
    WingetVersion              = Get-WingetVersion
    WindowsBuild               = [System.Environment]::OSVersion.Version
    DesktopAppInstallerVersion = Get-CorePackageVersion -Name 'Microsoft.DesktopAppInstaller'
    WindowsStoreVersion        = Get-CorePackageVersion -Name 'Microsoft.WindowsStore'
} | Format-List

$installed = Get-InstalledCodexSnapshot
Write-Step 'Installed package'
if ($null -eq $installed) {
    Write-Host 'Codex is not installed.'
}
else {
    $installed | Format-List
}

$pageMetadata = $null
Write-Step 'Microsoft Store page metadata'
if ($SkipStorePage) {
    Write-Host 'Skipped.'
}
else {
    try {
        $pageMetadata = Get-StorePageMetadata -Market $Market
        $pageMetadata | Format-List
    }
    catch {
        Write-Host ("Store page metadata lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

$manifestSummary = $null
Write-Step 'Store manifest endpoint'
if ($SkipManifest) {
    Write-Host 'Skipped.'
}
else {
    try {
        $manifestSummary = Get-ManifestSummary -Market $Market
        $manifestSummary | Format-List
    }
    catch {
        Write-Host ("Manifest lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

$wingetCheck = $null
Write-Step 'Official winget update check'
if ($SkipWingetCheck) {
    Write-Host 'Skipped.'
}
else {
    try {
        $wingetCheck = Get-CodexUpgradeCheck

        [pscustomobject]@{
            ExitCode  = $wingetCheck.ExitCode
            NoUpdates = $wingetCheck.NoUpdates
        } | Format-List

        if (-not [string]::IsNullOrWhiteSpace($wingetCheck.Output)) {
            Write-Host $wingetCheck.Output
        }
    }
    catch {
        Write-Host ("winget check failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

Write-Step ("Recent Codex events ({0} days)" -f $HistoryDays)
$events = @(Get-CodexRelevantEvents -Days $HistoryDays -MaxEvents $MaxHistoryEvents)
if ($events.Count -eq 0) {
    Write-Host 'No recent Codex Store/AppX events were found.'
}
else {
    $events | Select-Object TimeCreated, Source, Id, MessagePreview | Format-Table -Wrap -AutoSize
}

Write-Step 'Verdict'
if ($null -eq $installed) {
    Write-Host 'Codex is not installed locally.'
}
else {
    Write-Host ("Installed version: {0}" -f $installed.Version)
}

if ($null -ne $pageMetadata) {
    if ([string]::IsNullOrWhiteSpace([string]$pageMetadata.PublicVersion)) {
        Write-Host 'Public Microsoft Store page does not expose a plain package version number for this app.'
    }
    else {
        Write-Host ("Public Microsoft Store page version field: {0}" -f $pageMetadata.PublicVersion)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$pageMetadata.LastUpdateDateUtc)) {
        Write-Host ("Store page last update metadata: {0}" -f $pageMetadata.LastUpdateDateUtc)
    }
}

if ($null -ne $manifestSummary) {
    Write-Host ("Manifest PackageVersion field: {0}" -f $manifestSummary.PackageVersion)
}

if ($null -ne $wingetCheck) {
    if ($wingetCheck.NoUpdates) {
        Write-Host 'Official winget update check found no newer version in the configured Microsoft Store source.'
    }
    elseif ($wingetCheck.ExitCode -eq 0) {
        Write-Host 'Official winget update check completed without the standard no-update markers. Review the output above.'
    }
    else {
        Write-Host ("Official winget update check failed with exit code {0}. Review the output above." -f $wingetCheck.ExitCode)
    }
}
