[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/CodexStore.Common.ps1')

# Keep the real parser and probe; replace only the Windows network boundary.
$script:probeCalls = 0
function Test-NetConnection {
    param($ComputerName, $Port, $InformationLevel, $WarningAction)
    if ($ComputerName -ne '127.0.0.1' -or $Port -ne 2080 -or $InformationLevel -ne 'Quiet') {
        throw 'Unexpected network probe arguments'
    }
    $script:probeCalls++
    return $script:listening
}
$endpoint = Get-LoopbackEndpointFromText -Text 'http=127.0.0.1:2080;https=127.0.0.1:2080'
if ($null -eq $endpoint) { throw 'Expected loopback proxy endpoint' }
$script:listening = $true
if (-not (Test-TcpPort -Host $endpoint.Host -Port $endpoint.Port)) {
    throw 'LISTENING_PROXY: expected true'
}
$script:listening = $false
if (Test-TcpPort -Host $endpoint.Host -Port $endpoint.Port) {
    throw 'CLOSED_PROXY: expected false'
}
if ($script:probeCalls -ne 2) { throw 'Both probes must reach the network boundary' }
Write-Host 'PASS: listening and closed loopback proxies reach the network probe without overwriting PowerShell Host'
