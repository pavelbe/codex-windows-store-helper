[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptsRoot = Join-Path $repoRoot 'scripts'

$tests = @(
    @{
        Name       = 'Status'
        Path       = Join-Path $scriptsRoot 'Get-CodexStoreStatus.ps1'
        Parameters = @{
            HistoryDays = 2
        }
    },
    @{
        Name       = 'Repair-CheckOnly'
        Path       = Join-Path $scriptsRoot 'Repair-StoreNetwork.ps1'
        Parameters = @{}
    },
    @{
        Name       = 'Doctor'
        Path       = Join-Path $scriptsRoot 'Get-CodexAppDoctor.ps1'
        Parameters = @{
            HistoryDays      = 2
            MaxHistoryEvents = 6
        }
    },
    @{
        Name       = 'Install-Idempotent'
        Path       = Join-Path $scriptsRoot 'Install-Codex.ps1'
        Parameters = @{}
    },
    @{
        Name       = 'Update-Check'
        Path       = Join-Path $scriptsRoot 'Update-Codex.ps1'
        Parameters = @{}
    }
)

foreach ($test in $tests) {
    Write-Host ''
    Write-Host ("### {0}" -f $test.Name) -ForegroundColor Yellow
    $parameters = @{}
    if ($null -ne $test.Parameters) {
        $parameters = $test.Parameters
    }

    & $test.Path @parameters
}

Write-Host ''
Write-Host 'Smoke tests completed successfully.' -ForegroundColor Green
