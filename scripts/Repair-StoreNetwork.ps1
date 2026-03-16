[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$ResetBrokenLoopbackWinHttpProxy,
    [switch]$ResetStoreCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CodexStore.Common.ps1')

Assert-WingetAvailable

Write-Step 'Current status'
& (Join-Path $PSScriptRoot 'Get-CodexStoreStatus.ps1')

if (-not $ResetBrokenLoopbackWinHttpProxy -and -not $ResetStoreCache) {
    Write-Host ''
    Write-Host 'No mutating switches were provided. Reporting only.'
    Write-Host 'Use -ResetBrokenLoopbackWinHttpProxy and/or -ResetStoreCache to apply fixes.'
    return
}

if ($ResetBrokenLoopbackWinHttpProxy) {
    $winHttpRaw = Get-WinHttpProxyRaw
    $endpoint = Get-LoopbackEndpointFromText -Text $winHttpRaw

    if ($null -eq $endpoint) {
        Write-Step 'WinHTTP proxy is not a loopback endpoint; nothing to reset.'
    }
    else {
        $isListening = Test-TcpPort -Host $endpoint.Host -Port $endpoint.Port
        if ($isListening) {
            Write-Step ("Loopback WinHTTP proxy {0}:{1} is alive; leaving it unchanged." -f $endpoint.Host, $endpoint.Port)
        }
        elseif ($PSCmdlet.ShouldProcess('WinHTTP proxy', 'netsh winhttp reset proxy')) {
            Write-Step ("Resetting broken loopback WinHTTP proxy {0}:{1}" -f $endpoint.Host, $endpoint.Port)
            netsh winhttp reset proxy | Out-Host
        }
    }
}

if ($ResetStoreCache -and $PSCmdlet.ShouldProcess('Microsoft Store cache', 'wsreset.exe')) {
    Write-Step 'Running wsreset.exe'
    Start-Process wsreset.exe -Wait
}

Write-Step 'Status after requested actions'
& (Join-Path $PSScriptRoot 'Get-CodexStoreStatus.ps1')
