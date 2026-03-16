[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptsRoot = Join-Path $repoRoot 'scripts'

$tests = @(
    @{
        Name = 'Status'
        Path = Join-Path $scriptsRoot 'Get-CodexStoreStatus.ps1'
        Args = @()
    },
    @{
        Name = 'Repair-CheckOnly'
        Path = Join-Path $scriptsRoot 'Repair-StoreNetwork.ps1'
        Args = @()
    },
    @{
        Name = 'Install-Idempotent'
        Path = Join-Path $scriptsRoot 'Install-Codex.ps1'
        Args = @()
    },
    @{
        Name = 'Update-Check'
        Path = Join-Path $scriptsRoot 'Update-Codex.ps1'
        Args = @()
    }
)

foreach ($test in $tests) {
    Write-Host ''
    Write-Host ("### {0}" -f $test.Name) -ForegroundColor Yellow
    $arguments = @()
    if ($null -ne $test.Args) {
        $arguments += $test.Args
    }

    & $test.Path @arguments
}

Write-Host ''
Write-Host 'Smoke tests completed successfully.' -ForegroundColor Green
