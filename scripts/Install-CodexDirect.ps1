# Canonical source: pavelbe/codex-windows-store-helper. HCA carries an exact copy.
# Official distribution: https://learn.chatgpt.com/docs/enterprise/windows-deployment
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$DownloadOnly,
    [string]$PackagePath,
    [switch]$OpenApp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CodexDevice {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    $architecture = switch ($arch) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { throw "Unsupported Windows architecture: $arch. x64 or Arm64 is required." }
    }
    $os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        Architecture = $architecture
        Version = [version]("10.0.{0}.{1}" -f $os.CurrentBuildNumber, $os.UBR)
        Url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-$architecture.msix"
    }
}

function Get-CodexDirectPackage {
    $packages = @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop)
    if ($packages.Count -gt 1) { throw 'Multiple Codex packages found; inspect Get-AppxPackage OpenAI.Codex first.' }
    if ($packages.Count -eq 1) {
        if ($packages[0].PackageFamilyName -ne 'OpenAI.Codex_2p2nqsd0c76g0') {
            throw 'Unexpected installed Codex package family. No changes made.'
        }
        return $packages[0]
    }
}

function Receive-CodexMsix {
    param([Parameter(Mandatory = $true)]$Device)
    $curl = Get-Command curl.exe -ErrorAction Stop
    $directory = Join-Path $env:LOCALAPPDATA ('CodexAppInstaller\' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $partial = Join-Path $directory ("ChatGPT-{0}.msix.partial" -f $Device.Architecture)
    $destination = $partial.Substring(0, $partial.Length - '.partial'.Length)
    Write-Host "Downloading official package: $($Device.Url)"
    Write-Host 'The package can exceed 700 MiB. curl displays progress; timeout is 8 minutes. Retry explicitly after a failure.'
    & $curl.Source --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 480 --output $partial --url $Device.Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed (curl exit $LASTEXITCODE). No app was removed. Incomplete file: $partial"
    }
    if (-not (Test-Path -LiteralPath $partial -PathType Leaf) -or (Get-Item -LiteralPath $partial).Length -eq 0) {
        throw 'Download produced no package. No app was removed.'
    }
    Move-Item -LiteralPath $partial -Destination $destination -ErrorAction Stop
    return $destination
}

function Read-CodexMsix {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Device)
    if ([IO.Path]::GetExtension($Path) -ine '.msix') { throw 'Select a complete .msix file, not an installer EXE, bundle or partial download.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ([string]$signature.Status -ne 'Valid') {
        throw "MSIX signature is not trusted: $($signature.Status). Do not disable signature checks or install certificates to bypass this error."
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entries = @($zip.Entries | Where-Object FullName -ceq 'AppxManifest.xml')
        if ($entries.Count -ne 1 -or $entries[0].Length -gt 1048576) { throw 'Invalid MSIX manifest.' }
        $stream = $entries[0].Open()
        $reader = $null
        try {
            $xmlSettings = New-Object System.Xml.XmlReaderSettings
            $xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
            $xmlSettings.XmlResolver = $null
            $reader = [Xml.XmlReader]::Create($stream, $xmlSettings)
            $manifest = New-Object Xml.XmlDocument
            $manifest.XmlResolver = $null
            $manifest.Load($reader)
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
            $stream.Dispose()
        }
    }
    finally { $zip.Dispose() }
    $ns = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
    $ns.AddNamespace('a', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $identity = $manifest.SelectSingleNode('/a:Package/a:Identity', $ns)
    if ($null -eq $identity -or $identity.GetAttribute('Name') -cne 'OpenAI.Codex' -or
        $identity.GetAttribute('Publisher') -cne 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B') {
        throw 'Wrong MSIX identity or publisher. Expected the official OpenAI.Codex package; no changes made.'
    }
    if ($identity.GetAttribute('ProcessorArchitecture') -ine $Device.Architecture) {
        throw "MSIX architecture does not match this device ($($Device.Architecture))."
    }
    $families = @($manifest.SelectNodes('/a:Package/a:Dependencies/a:TargetDeviceFamily', $ns))
    $compatible = @($families | Where-Object {
        $_.GetAttribute('Name') -in @('Windows.Desktop', 'Windows.Universal') -and
        [version]$_.GetAttribute('MinVersion') -le $Device.Version
    })
    if ($compatible.Count -eq 0) { throw "This MSIX does not support Windows $($Device.Version)." }
    foreach ($dependency in $manifest.SelectNodes('/a:Package/a:Dependencies/a:PackageDependency', $ns)) {
        $name = $dependency.GetAttribute('Name')
        $publisher = $dependency.GetAttribute('Publisher')
        $minimum = [version]$dependency.GetAttribute('MinVersion')
        $found = @(Get-AppxPackage -Name $name -ErrorAction Stop | Where-Object {
            $_.Publisher -ceq $publisher -and [version]$_.Version -ge $minimum -and
            [string]$_.Architecture -in @($Device.Architecture, 'Neutral') -and [string]$_.Status -eq 'Ok'
        })
        if ($found.Count -eq 0) { throw "Missing dependency: $name >= $minimum ($($Device.Architecture)). Obtain it from its official publisher; no changes made." }
    }
    [pscustomobject]@{
        Path = $Path
        Version = [version]$identity.GetAttribute('Version')
        Architecture = $identity.GetAttribute('ProcessorArchitecture')
        Signature = [string]$signature.Status
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

function Write-CodexDeploymentHelp {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host $Message -ForegroundColor Red
    Write-Host 'The helper did not uninstall the app, delete data, stop agents, or change Windows permissions.'
    if ($Message -match '80070005|windows.firewall') {
        Write-Host 'Access denied: this is not proof that the account lacks administrator membership.'
        Write-Host 'Check BFE, mpssvc, EventLog and AppXSvc plus the AppX ActivityId below. Do not grant Everyone access or disable the firewall/UAC.'
    }
    if ($Message -match '80073D02') { Write-Host 'Save work and close only the desktop app normally, then retry. Do not restart WSL.' }
    if ($Message -match '80073CF3') { Write-Host 'A package dependency or conflict blocked deployment. Read the AppX log for the named package.' }
    if ($Message -match '80073D06') { Write-Host 'A newer version is already installed. Downgrade was not requested.' }
    $activity = [regex]::Match($Message, '(?i)(?:ActivityId|Activity ID)[^0-9a-f]+([0-9a-f]{8}-[0-9a-f-]{27})')
    if ($activity.Success) { Write-Host ("Details: Get-AppPackageLog -ActivityID {0}" -f $activity.Groups[1].Value) }
    Write-Host 'Event Viewer: Applications and Services Logs > Microsoft > Windows > AppXDeployment-Server > Operational.'
    Get-Service EventLog,BFE,mpssvc,AppXSvc -ErrorAction SilentlyContinue | Select-Object Name,Status | Format-Table -AutoSize
}

function Invoke-CodexDirectInstall {
    [CmdletBinding()]
    param([switch]$CheckOnly, [switch]$DownloadOnly, [string]$PackagePath, [switch]$OpenApp)
    if ($CheckOnly -and $DownloadOnly) { throw 'Choose either -CheckOnly or -DownloadOnly.' }
    if ($OpenApp -and ($CheckOnly -or $DownloadOnly)) { throw '-OpenApp cannot be combined with a read/download-only mode.' }
    $device = Get-CodexDevice
    $before = Get-CodexDirectPackage
    Write-Host "Windows: $($device.Version); architecture: $($device.Architecture)"
    if ($null -eq $before) { Write-Host 'Installed: no' } else { Write-Host "Installed: $($before.Version); status: $($before.Status)" }
    if ($CheckOnly -and -not $PackagePath) {
        $metadata = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $device.Url -TimeoutSec 25
        Write-Host "Official package URL: $($device.Url)"
        Write-Host ("Available version (HTTP metadata, not signature proof): {0}; bytes: {1}" -f $metadata.Headers['x-ms-meta-package_version'], $metadata.Headers['Content-Length'])
        Write-Host 'Check-only: no download, installation or data cleanup.'
        return
    }
    if (-not $PackagePath) { $PackagePath = Receive-CodexMsix -Device $device }
    $resolved = (Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).ProviderPath
    # Hold a read lease through verification and deployment: no writer/delete sharing.
    $lease = [IO.File]::Open($resolved, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $candidate = Read-CodexMsix -Path $resolved -Device $device
        $candidate | Format-List
        if ($CheckOnly -or $DownloadOnly) {
            Write-Host 'Package verified; no installation or data cleanup.'
            return
        }
        # Re-read after the download; Store's updater may have changed the installed version.
        $before = Get-CodexDirectPackage
        if ($null -ne $before -and [version]$before.Version -gt $candidate.Version) {
            throw "Refusing downgrade: installed $($before.Version), downloaded $($candidate.Version)."
        }
        Write-Host 'Applying the signed package for the current Windows user. Existing app data and WSL are preserved.'
        try { Add-AppxPackage -Path $candidate.Path -ErrorAction Stop }
        catch {
            Write-CodexDeploymentHelp -Message ($_ | Out-String)
            throw
        }
        $after = Get-CodexDirectPackage
        if ($null -eq $after -or [version]$after.Version -lt $candidate.Version -or [string]$after.Status -ne 'Ok') {
            throw 'Deployment returned without a healthy registered package of the expected version. Installation is NOT confirmed.'
        }
        Write-Host "Installed and registered: $($after.Version); status: $($after.Status). Launch/UI behavior still needs a manual check."
        if ($OpenApp) { Start-Process 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App' }
    }
    finally { $lease.Dispose() }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-CodexDirectInstall @PSBoundParameters }
