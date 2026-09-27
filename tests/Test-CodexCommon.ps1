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

# Exercise real Store entrypoints; the repair boundary reports bound switches
# and stops before any network, deployment, proxy or Store-cache operation.
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('codex-store-options-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
try {
    $scripts = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
    foreach ($entry in @('Install-Codex.ps1', 'Update-Codex.ps1')) {
        Copy-Item (Join-Path $scripts $entry) $fixture
    }
    @'
function Assert-WingetAvailable {}
function Write-Step {}
function Get-InstalledCodexPackage { [pscustomobject]@{Version='26.1.0.0'} }
function Get-InstalledCodexSnapshot {}
'@ | Set-Content (Join-Path $fixture 'CodexStore.Common.ps1') -Encoding ASCII
    @'
[CmdletBinding()]
param([switch]$ResetBrokenLoopbackWinHttpProxy, [switch]$ResetStoreCache)
throw ("REPAIR_ARGS:{0}:{1}" -f [bool]$ResetBrokenLoopbackWinHttpProxy, [bool]$ResetStoreCache)
'@ | Set-Content (Join-Path $fixture 'Repair-StoreNetwork.ps1') -Encoding ASCII
    $cases = @(
        @{Options=@{RepairBrokenLoopbackWinHttpProxy=$true}; Expected='REPAIR_ARGS:True:False'},
        @{Options=@{ResetStoreCache=$true}; Expected='REPAIR_ARGS:False:True'},
        @{Options=@{RepairBrokenLoopbackWinHttpProxy=$true; ResetStoreCache=$true}; Expected='REPAIR_ARGS:True:True'}
    )
    $forwardingChecks = 0
    foreach ($entry in @('Install-Codex.ps1', 'Update-Codex.ps1')) {
        # Without explicit switches, even the repair boundary must not run.
        & (Join-Path $fixture $entry) -Source Store
        $forwardingChecks++
        foreach ($case in $cases) {
            $options = $case.Options
            $observed = 'NO_REPAIR_CALL'
            try { & (Join-Path $fixture $entry) -Source Store @options }
            catch { $observed = $_.Exception.Message }
            if ($observed -cne $case.Expected) {
                throw ("STORE_REPAIR_FORWARDING: {0}: expected {1}; received {2}" -f $entry, $case.Expected, $observed)
            }
            $forwardingChecks++
        }
    }
    Write-Host ("PASS: {0} Store entrypoint option checks; repair boundary mocked" -f $forwardingChecks)
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
