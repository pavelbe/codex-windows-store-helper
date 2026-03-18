[CmdletBinding()]
param(
    [int]$HistoryDays = 7,
    [switch]$SkipHistory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

Assert-WingetAvailable

$codex = Get-InstalledCodexSnapshot
$winHttpRaw = Get-WinHttpProxyRaw
$userProxy = Get-UserProxyConfig
$winHttpLoopback = Get-LoopbackEndpointFromText -Text $winHttpRaw
$userLoopback = Get-LoopbackEndpointFromText -Text $userProxy.ProxyServer

Write-Step 'Environment'
[pscustomobject]@{
    WingetVersion               = Get-WingetVersion
    WindowsBuild               = [System.Environment]::OSVersion.Version
    DesktopAppInstallerVersion = Get-CorePackageVersion -Name 'Microsoft.DesktopAppInstaller'
    WindowsStoreVersion        = Get-CorePackageVersion -Name 'Microsoft.WindowsStore'
} | Format-List

Write-Step 'Codex'
if ($null -eq $codex) {
    Write-Host 'Codex is not installed.'
}
else {
    $codex | Format-List
}

Write-Step 'Proxy'
[pscustomobject]@{
    WinHttpProxyText = $winHttpRaw -replace "(`r`n|`n)", ' | '
    UserProxyEnabled = $userProxy.ProxyEnable
    UserProxyServer  = $userProxy.ProxyServer
    UserAutoConfig   = $userProxy.AutoConfigURL
} | Format-List

if ($null -ne $winHttpLoopback) {
    [pscustomobject]@{
        Type      = 'WinHTTP loopback proxy'
        Host      = $winHttpLoopback.Host
        Port      = $winHttpLoopback.Port
        IsListening = (Test-TcpPort -Host $winHttpLoopback.Host -Port $winHttpLoopback.Port)
    } | Format-List
}

if ($null -ne $userLoopback) {
    [pscustomobject]@{
        Type        = 'User loopback proxy'
        Host        = $userLoopback.Host
        Port        = $userLoopback.Port
        IsListening = (Test-TcpPort -Host $userLoopback.Host -Port $userLoopback.Port)
    } | Format-List
}

Write-Step 'Update workflow'
if ($null -eq $codex) {
    Write-Host 'Codex is not installed. Run Install-Codex.ps1 to install it from the official Microsoft Store source.'
}
else {
    Write-Host 'For this msstore package, winget show does not expose a reliable plain version number from the Store source.'
    Write-Host 'Use Update-Codex.ps1 when you want the official update check and upgrade flow.'
}

Write-Step ("Recent Codex Store/AppX history ({0} days)" -f $HistoryDays)
if ($SkipHistory) {
    Write-Host 'Skipped.'
}
else {
    $events = @(Get-CodexRelevantEvents -Days $HistoryDays)
    if ($events.Count -eq 0) {
        Write-Host 'No matching Codex events were found in the selected time window.'
    }
    else {
        $events |
            Select-Object TimeCreated, Source, Id, MessagePreview |
            Format-Table -Wrap -AutoSize
    }
}
