[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem (Join-Path $root 'scripts'),$PSScriptRoot -Filter '*.ps1' -File)
if ($files.Count -lt 8) { throw 'Script inventory unexpectedly empty/incomplete' }
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ("PowerShell parse failed: {0}: {1}" -f $file.Name, ($errors.Message -join '; ')) }
}
Write-Host ("PASS: parsed {0} PowerShell scripts" -f $files.Count)
& (Join-Path $PSScriptRoot 'Test-CodexCommon.ps1')
& (Join-Path $PSScriptRoot 'Test-CodexDirect.ps1')
Write-Host 'Smoke complete: offline contract tests; no app installation, Store reset or network request.'
