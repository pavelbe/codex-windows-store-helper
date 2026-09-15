[CmdletBinding()]
param([switch]$ReinstallSafetyOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('codex-direct-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$oldLocalAppData = $env:LOCALAPPDATA
try {
    # Execute the real reinstall entrypoint with failing distribution boundaries.
    # Every destructive cmdlet is confined/intercepted; no installed app is touched.
    Copy-Item (Join-Path $scripts 'Reinstall-Codex.ps1') $fixture
    Copy-Item (Join-Path $scripts 'Install-CodexDirect.ps1') $fixture
    @'
$script:CodexStoreId = '9PLM9XGG6VKS'
function Assert-WingetAvailable {}
function Write-Step {}
function Get-LatestOpenAiCodexAppRelease {}
function Get-DisplayCatalogSummary {}
function Get-InstalledCodexSnapshot { [pscustomobject]@{Version='26.1.0.0';PackageFullName='OpenAI.Codex_test'} }
function Invoke-WingetWithCapture { [pscustomobject]@{ExitCode=22;Output='fixture download failure'} }
'@ | Set-Content (Join-Path $fixture 'CodexStore.Common.ps1') -Encoding UTF8
    $data = Join-Path $fixture 'OpenAI.Codex_2p2nqsd0c76g0'
    $null = New-Item -ItemType Directory -Path $data
    $sentinel = Join-Path $data 'session.txt'
    Set-Content $sentinel 'KEEP_THIS_SESSION' -Encoding ASCII
    $env:LOCALAPPDATA = $fixture
    $script:removed = $false
    & {
        function Get-ChildItem {
            param($LiteralPath)
            if ($LiteralPath -like '*Packages') { Microsoft.PowerShell.Management\Get-Item -LiteralPath $data }
            else { throw 'Unexpected fixture enumeration' }
        }
        function Test-Path {
            param($LiteralPath, $PathType)
            if ($LiteralPath -like '*Packages') { return $true }
            Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
        }
        function Get-Process {}
        function Stop-Process {}
        function Start-Sleep {}
        function Remove-AppxPackage { $script:removed = $true }
        function Remove-Item {
            param($LiteralPath)
            if ($LiteralPath -ne $data) { throw 'Refusing fixture escape' }
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $data -Recurse -Force
        }
        function Get-AppxPackage {
            [pscustomobject]@{Version='26.1.0.0';PackageFamilyName='OpenAI.Codex_2p2nqsd0c76g0';Status='Ok'}
        }
        function Get-Command { [pscustomobject]@{Source='Invoke-FailedDownload'} }
        function Invoke-FailedDownload { $global:LASTEXITCODE = 22 }
        $failed = $false
        try { & (Join-Path $fixture 'Reinstall-Codex.ps1') }
        catch {
            if ($_.Exception.Message -notmatch 'winget install failed|Download failed') { throw }
            $failed = $true
        }
        if (-not $failed) { throw 'REINSTALL_FAILURE_PROPAGATES: expected a download failure' }
    }
    if ($script:removed -or -not (Test-Path -LiteralPath $sentinel)) {
        throw 'REINSTALL_PRESERVES_DATA: expected installed app and session data intact after download failure'
    }
    Write-Host 'PASS: failed replacement download preserves app registration and session data'
    if ($ReinstallSafetyOnly) { return }

    # Public entrypoints must forward direct options without reaching Store/common code.
    @'
param([switch]$CheckOnly,[switch]$DownloadOnly,[string]$PackagePath,[switch]$OpenApp)
[pscustomobject]@{CheckOnly=[bool]$CheckOnly;DownloadOnly=[bool]$DownloadOnly;PackagePath=$PackagePath;OpenApp=[bool]$OpenApp}
'@ | Set-Content (Join-Path $fixture 'Install-CodexDirect.ps1') -Encoding ASCII
    foreach ($entry in @('Install-Codex.ps1','Update-Codex.ps1','Reinstall-Codex.ps1')) {
        Copy-Item (Join-Path $scripts $entry) $fixture -Force
        $forwarded = & (Join-Path $fixture $entry) -CheckOnly -PackagePath 'C:\Path With Spaces\ChatGPT-x64.msix'
        if (-not $forwarded.CheckOnly -or $forwarded.DownloadOnly -or $forwarded.OpenApp -or
            $forwarded.PackagePath -ne 'C:\Path With Spaces\ChatGPT-x64.msix') { throw "ENTRYPOINT_FORWARDING_FAILED: $entry" }
    }
    Write-Host 'PASS: three public entrypoints preserve direct options and quoted paths'

    . (Join-Path $scripts 'Install-CodexDirect.ps1')
    $device = [pscustomobject]@{Architecture='x64';Version=[version]'10.0.22631.0';Url='https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem,System.IO.Compression
    function New-TestMsix {
        param([string]$Name='OpenAI.Codex', [string]$Publisher='CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B', [string]$Arch='x64', [string]$Minimum='10.0.19041.0', [string]$Extra='')
        $path = Join-Path $fixture ([guid]::NewGuid().ToString('N') + '.msix')
        $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $zip.CreateEntry('AppxManifest.xml')
            $writer = New-Object IO.StreamWriter($entry.Open())
            try { $writer.Write(('<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"><Identity Name="{0}" Publisher="{1}" ProcessorArchitecture="{2}" Version="26.903.8094.0"/><Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="{3}"/>{4}</Dependencies></Package>' -f $Name,$Publisher,$Arch,$Minimum,$Extra)) }
            finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
        $path
    }
    function Assert-Rejected {
        param([scriptblock]$Operation, [string]$Message)
        $rejected = $false
        try { & $Operation | Out-Null }
        catch { if ($_.Exception.Message -notmatch $Message) { throw }; $rejected = $true }
        if (-not $rejected) { throw "EXPECTED_REJECTION: $Message" }
        $script:checks++
    }
    $script:checks = 0
    $script:signatureStatus = 'Valid'
    function Get-AuthenticodeSignature { [pscustomobject]@{Status=$script:signatureStatus} }
    function Get-AppxPackage {}
    $valid = New-TestMsix
    $metadata = Read-CodexMsix -Path $valid -Device $device
    if ($metadata.Version -ne [version]'26.903.8094.0') { throw 'Manifest version was not read' }
    $script:checks++
    $script:signatureStatus = 'HashMismatch'
    Assert-Rejected { Read-CodexMsix -Path $valid -Device $device } 'signature is not trusted'
    $script:signatureStatus = 'Valid'
    $wrongName = New-TestMsix -Name Other.App
    Assert-Rejected { Read-CodexMsix -Path $wrongName -Device $device } 'Wrong MSIX identity'
    $wrongPublisher = New-TestMsix -Publisher 'CN=Other'
    Assert-Rejected { Read-CodexMsix -Path $wrongPublisher -Device $device } 'Wrong MSIX identity'
    $wrongArch = New-TestMsix -Arch arm64
    Assert-Rejected { Read-CodexMsix -Path $wrongArch -Device $device } 'architecture does not match'
    $armDevice = [pscustomobject]@{Architecture='arm64';Version=$device.Version}
    $armMetadata = Read-CodexMsix -Path $wrongArch -Device $armDevice
    if ($armMetadata.Architecture -ne 'arm64') { throw 'ARM64_MANIFEST_NOT_READ' }
    $script:checks++
    $newerOs = New-TestMsix -Minimum '10.0.99999.0'
    Assert-Rejected { Read-CodexMsix -Path $newerOs -Device $device } 'does not support Windows'
    $needsFramework = New-TestMsix -Extra '<PackageDependency Name="Test.Framework" Publisher="CN=Test" MinVersion="1.0.0.0"/>'
    Assert-Rejected { Read-CodexMsix -Path $needsFramework -Device $device } 'Missing dependency'

    # Flow tests keep the production manifest/signature gate; only OS/network effects are doubled.
    function Get-CodexDevice { $device }
    $script:package = $null
    function Get-AppxPackage { if ($null -ne $script:package) { $script:package } }
    $script:downloads = 0
    function Receive-CodexMsix { $script:downloads++; $valid }
    $script:installs = 0
    $script:installMode = 'success'
    function Add-AppxPackage {
        $script:installs++
        if ($script:installMode -eq 'failure') { throw 'Fixture deployment error 0x80070005' }
        if ($script:installMode -eq 'missing') { return }
        $script:package = [pscustomobject]@{Version='26.903.8094.0';PackageFamilyName='OpenAI.Codex_2p2nqsd0c76g0';Status='Ok'}
    }
    function Invoke-WebRequest { [pscustomobject]@{Headers=@{'x-ms-meta-package_version'='26.903.8094.0';'Content-Length'='123'}} }
    function Get-Service {}
    function Start-Process { throw 'Unexpected app launch in tests' }
    Invoke-CodexDirectInstall -CheckOnly
    if ($script:installs -ne 0 -or $script:downloads -ne 0) { throw 'CHECK_ONLY_MUTATED: expected no download/install' }
    $script:checks++
    Invoke-CodexDirectInstall -PackagePath $valid -CheckOnly
    Invoke-CodexDirectInstall -DownloadOnly
    if ($script:installs -ne 0 -or $script:downloads -ne 1) { throw 'DOWNLOAD_ONLY_INSTALLED: expected download without installation' }
    $script:checks++
    $script:signatureStatus = 'NotSigned'
    Assert-Rejected { Invoke-CodexDirectInstall -PackagePath $valid } 'signature is not trusted'
    if ($script:installs -ne 0) { throw 'UNTRUSTED_PACKAGE_INSTALLED' }
    $script:signatureStatus = 'Valid'
    $script:package = [pscustomobject]@{Version='99.0.0.0';PackageFamilyName='OpenAI.Codex_2p2nqsd0c76g0';Status='Ok'}
    Assert-Rejected { Invoke-CodexDirectInstall -PackagePath $valid } 'Refusing downgrade'
    if ($script:installs -ne 0) { throw 'DOWNGRADE_ATTEMPTED' }
    $script:package = $null
    $script:installMode = 'failure'
    Assert-Rejected { Invoke-CodexDirectInstall -PackagePath $valid } 'Fixture deployment error'
    $script:installMode = 'missing'
    Assert-Rejected { Invoke-CodexDirectInstall -PackagePath $valid } 'Installation is NOT confirmed'
    $script:installMode = 'success'
    Invoke-CodexDirectInstall -PackagePath $valid
    if ($script:installs -ne 3 -or $null -eq $script:package) { throw 'INSTALL_FLOW_NOT_EXERCISED' }
    $script:checks++
    Assert-Rejected { Invoke-CodexDirectInstall -CheckOnly -DownloadOnly } 'Choose either'
    Assert-Rejected { Invoke-CodexDirectInstall -CheckOnly -OpenApp } 'cannot be combined'
    Write-Host ("PASS: {0} direct-install checks; OS signature/deployment/network boundaries mocked, no live installation" -f $script:checks)
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $fixture -Recurse -Force
}
