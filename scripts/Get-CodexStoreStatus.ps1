[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

Assert-WingetAvailable

$codex = Get-InstalledCodexPackage
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
    [pscustomobject]@{
        Name            = $codex.Name
        Version         = [string]$codex.Version
        Status          = [string]$codex.Status
        InstallLocation = $codex.InstallLocation
    } | Format-List
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
