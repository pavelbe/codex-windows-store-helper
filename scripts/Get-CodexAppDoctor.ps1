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

$latestOpenAiRelease = $null
Write-Step 'OpenAI Codex app changelog'
try {
    $latestOpenAiRelease = Get-LatestOpenAiCodexAppRelease
    [pscustomobject]@{
        LatestVersion = $latestOpenAiRelease.Version
        PublishedUtc  = $latestOpenAiRelease.DateText
        Url           = $latestOpenAiRelease.Url
    } | Format-List
}
catch {
    Write-Host ("OpenAI changelog lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$displayCatalogSummary = $null
Write-Step 'Microsoft display catalog'
try {
    $displayCatalogSummary = Get-DisplayCatalogSummary -Market $Market
    [pscustomobject]@{
        Market           = $Market
        PackageVersion   = $displayCatalogSummary.PackageVersion
        PackageFullName  = $displayCatalogSummary.PackageFullName
        LastModifiedDate = $displayCatalogSummary.LastModifiedDate
        SkuId            = $displayCatalogSummary.SkuId
    } | Format-List
}
catch {
    Write-Host ("Display catalog lookup failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
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

if ($null -ne $latestOpenAiRelease) {
    Write-Host ("Latest official OpenAI Codex app release: {0} ({1})" -f $latestOpenAiRelease.Version, $latestOpenAiRelease.DateText)
}

if ($null -ne $displayCatalogSummary) {
    Write-Host ("Display catalog package version for market {0}: {1}" -f $Market, $displayCatalogSummary.PackageVersion)
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

$installedTrain = if ($null -ne $installed) { Get-ReleaseTrain -VersionText $installed.Version } else { $null }
$latestTrain = if ($null -ne $latestOpenAiRelease) { Get-ReleaseTrain -VersionText $latestOpenAiRelease.Version } else { $null }
$compareLatest = Compare-ReleaseTrain -Left $installedTrain -Right $latestTrain
$availablePackageCompare = if ($null -ne $installed -and $null -ne $displayCatalogSummary) { ([version]$installed.Version).CompareTo([version]$displayCatalogSummary.PackageVersion) } else { $null }

if ($null -ne $compareLatest -and $compareLatest -lt 0 -and $null -ne $wingetCheck -and $wingetCheck.NoUpdates) {
    Write-Host 'OpenAI changelog shows a newer Codex app release, but winget is not offering it yet on this host.' -ForegroundColor Yellow
}

if ($null -ne $availablePackageCompare -and $availablePackageCompare -lt 0 -and $null -ne $wingetCheck -and $wingetCheck.NoUpdates) {
    Write-Host ("Microsoft display catalog already exposes a newer Codex package for market {0}, but winget is still not offering it as an update." -f $Market) -ForegroundColor Yellow
}
