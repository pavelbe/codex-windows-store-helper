Set-StrictMode -Version Latest

$script:CodexStoreId = '9PLM9XGG6VKS'
$script:CodexPackageName = 'OpenAI.Codex'
$script:CodexPackageFamilyName = 'OpenAI.Codex_2p2nqsd0c76g0'
$script:WingetNoUpdateExitCode = -1978335189
$script:OpenAiChangelogUrl = 'https://developers.openai.com/codex/changelog'

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-CodexStoreMetadata {
    [pscustomobject]@{
        StoreId           = $script:CodexStoreId
        PackageName       = $script:CodexPackageName
        PackageFamilyName = $script:CodexPackageFamilyName
    }
}

function Get-WingetVersion {
    try {
        return ((& winget --version) | Select-Object -First 1).Trim()
    }
    catch {
        return $null
    }
}

function Get-InstalledCodexPackage {
    Get-AppxPackage -Name $script:CodexPackageName -ErrorAction SilentlyContinue
}

function Get-InstalledCodexSnapshot {
    $package = Get-InstalledCodexPackage
    if ($null -eq $package) {
        return $null
    }

    $locationInfo = $null
    if (-not [string]::IsNullOrWhiteSpace($package.InstallLocation) -and (Test-Path -LiteralPath $package.InstallLocation)) {
        $locationInfo = Get-Item -LiteralPath $package.InstallLocation -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Name               = $package.Name
        Version            = [string]$package.Version
        Status             = [string]$package.Status
        InstallLocation    = $package.InstallLocation
        InstallTimeLocal   = if ($null -ne $locationInfo) { $locationInfo.CreationTime } else { $null }
        LastWriteTimeLocal = if ($null -ne $locationInfo) { $locationInfo.LastWriteTime } else { $null }
    }
}

function Get-ReleaseTrain {
    param(
        [AllowNull()]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '^(\d+)\.(\d+)')
    if (-not $match.Success) {
        return $null
    }

    return ('{0}.{1}' -f $match.Groups[1].Value, $match.Groups[2].Value)
}

function Compare-ReleaseTrain {
    param(
        [AllowNull()]
        [string]$Left,

        [AllowNull()]
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $null
    }

    return ([version]$Left).CompareTo([version]$Right)
}

function Get-WinHttpProxyRaw {
    (netsh winhttp show proxy | Out-String).Trim()
}

function Get-UserProxyConfig {
    try {
        $proxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        [pscustomobject]@{
            ProxyEnable   = [int]$proxy.ProxyEnable
            ProxyServer   = [string]$proxy.ProxyServer
            AutoConfigURL = [string]$proxy.AutoConfigURL
        }
    }
    catch {
        [pscustomobject]@{
            ProxyEnable   = 0
            ProxyServer   = ''
            AutoConfigURL = ''
        }
    }
}

function Get-LoopbackEndpointFromText {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $match = [regex]::Match($Text, '(?im)(127\.0\.0\.1|localhost|\[::1\]).{0,12}?(\d{2,5})')
    if (-not $match.Success) {
        return $null
    }

    $hostName = $match.Groups[1].Value
    if ($hostName -eq '[::1]') {
        $hostName = '::1'
    }

    [pscustomobject]@{
        Host = $hostName
        Port = [int]$match.Groups[2].Value
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Host,

        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        return [bool](Test-NetConnection -ComputerName $Host -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

function Invoke-WingetCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Step ("winget " + ($Arguments -join ' '))
    & winget @Arguments 2>&1 | Out-Host

    if ($null -eq $LASTEXITCODE) {
        return 0
    }

    return [int]$LASTEXITCODE
}

function Invoke-WingetWithCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $outputLines = (& winget @Arguments 2>&1)
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $outputText = (($outputLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()

    [pscustomobject]@{
        Arguments = $Arguments
        ExitCode  = $exitCode
        Output    = $outputText
        NoUpdates = Test-WingetNoUpdates -ExitCode $exitCode -Output $outputText
    }
}

function Test-WingetNoUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode,

        [AllowNull()]
        [string]$Output
    )

    return ($ExitCode -eq $script:WingetNoUpdateExitCode) -or (
        $ExitCode -eq 0 -and (
            $Output -like '*No available upgrade found*' -or
            $Output -like '*No newer package versions are available from the configured sources.*'
        )
    )
}

function Get-CodexUpgradeCheck {
    param(
        [switch]$IncludeInteractiveFlags,
        [switch]$VerboseLogs,
        [switch]$OpenLogs
    )

    $args = @(
        'upgrade',
        '--id', $script:CodexStoreId,
        '--source', 'msstore'
    )

    if ($IncludeInteractiveFlags) {
        $args += @(
            '--accept-source-agreements',
            '--accept-package-agreements',
            '--authentication-mode', 'interactive'
        )
    }

    if ($VerboseLogs) {
        $args += '--verbose-logs'
    }

    if ($OpenLogs) {
        $args += '--open-logs'
    }

    Invoke-WingetWithCapture -Arguments $args
}

function Get-LatestOpenAiCodexAppRelease {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $script:OpenAiChangelogUrl -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
    $content = [string]$response.Content
    $entryMatches = [regex]::Matches(
        $content,
        '(?is)<li id="codex-(?<date>20\d{2}-\d{2}-\d{2})-app(?:-mdx)?"[^>]*>.*?<time[^>]*>\s*\k<date>\s*</time>.*?<h3[^>]*>.*?(?<version>\d+\.\d+)\s*</span>'
    )
    if ($entryMatches.Count -eq 0) {
        throw 'Unable to parse Codex app releases from the OpenAI changelog.'
    }

    $seen = @{}
    $releases = New-Object System.Collections.Generic.List[object]
    foreach ($entryMatch in $entryMatches) {
        $dateText = $entryMatch.Groups['date'].Value
        $versionText = $entryMatch.Groups['version'].Value
        $key = '{0}|{1}' -f $dateText, $versionText
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $releases.Add([pscustomobject]@{
                DateText       = $dateText
                PublishedOnUtc = [datetime]::ParseExact($dateText, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                Version        = $versionText
                Url            = ('{0}#codex-{1}-app' -f $script:OpenAiChangelogUrl, $dateText)
            })
    }

    if ($releases.Count -eq 0) {
        throw 'Unable to parse Codex app version entries from the OpenAI changelog.'
    }

    return $releases | Sort-Object -Property PublishedOnUtc, Version -Descending | Select-Object -First 1
}

function Get-DisplayCatalogSummary {
    param(
        [string]$Market = 'US'
    )

    $url = 'https://displaycatalog.mp.microsoft.com/v7.0/products/lookup?fieldsTemplate=InstallAgent&market={0}&languages=ru,en,neutral&alternateId=PackageFamilyName&value={1}' -f $Market, $script:CodexPackageFamilyName
    $response = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'Mozilla/5.0' }

    $packages = New-Object System.Collections.Generic.List[object]
    foreach ($product in @($response.Products)) {
        foreach ($display in @($product.DisplaySkuAvailabilities)) {
            foreach ($package in @($display.Sku.Properties.Packages)) {
                $versionMatch = [regex]::Match([string]$package.PackageFullName, '_(\d+\.\d+\.\d+\.\d+)_')
                if (-not $versionMatch.Success) {
                    continue
                }

                $packages.Add([pscustomobject]@{
                        PackageVersion  = $versionMatch.Groups[1].Value
                        PackageFullName = [string]$package.PackageFullName
                        SkuId           = [string]$display.Sku.SkuId
                        LastModifiedDate = [string]$display.Sku.LastModifiedDate
                        LookupUrl       = $url
                    })
            }
        }
    }

    if ($packages.Count -eq 0) {
        throw 'Display catalog lookup did not return any Codex packages.'
    }

    return $packages | Sort-Object { [version]$_.PackageVersion } -Descending | Select-Object -First 1
}

function Assert-WingetAvailable {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install or repair Microsoft.DesktopAppInstaller first.'
    }
}

function Get-CorePackageVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $package = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $package) {
        return $null
    }

    return [string]$package.Version
}

function Get-CodexRelevantEvents {
    param(
        [int]$Days = 7,
        [int]$MaxEvents = 30
    )

    $start = (Get-Date).AddDays(-1 * [Math]::Abs($Days))
    $result = New-Object System.Collections.Generic.List[object]
    $definitions = @(
        @{
            Source  = 'AppXDeploymentServer'
            LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'
        },
        @{
            Source  = 'Store'
            LogName = 'Microsoft-Windows-Store/Operational'
        }
    )

    foreach ($definition in $definitions) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                    LogName = $definition.LogName
                    StartTime = $start
                } -ErrorAction Stop |
                Where-Object {
                    $_.Message -match 'OpenAI\.Codex' -or
                    $_.Message -match '9PLM9XGG6VKS'
                } |
                Select-Object -First $MaxEvents

            foreach ($event in $events) {
                $message = [string]$event.Message
                $message = $message -replace "(`r`n|`n|`r)+", ' '
                $message = $message -replace '\s{2,}', ' '
                if ($message.Length -gt 220) {
                    $message = $message.Substring(0, 220) + '...'
                }

                $result.Add([pscustomobject]@{
                    Source         = $definition.Source
                    TimeCreated    = $event.TimeCreated
                    Id             = $event.Id
                    Level          = $event.LevelDisplayName
                    MessagePreview = $message
                })
            }
        }
        catch {
        }
    }

    $result | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents
}

function Get-StorePageMetadata {
    param(
        [string]$Market = 'US'
    )

    $url = "https://apps.microsoft.com/detail/{0}?hl=en-us&gl={1}" -f $script:CodexStoreId, $Market
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
    $line = ($response.Content -split "`n" | Where-Object { $_ -like '*window.pageMetadata = *' } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw 'Unable to find window.pageMetadata on the Microsoft Store page.'
    }

    $jsonText = $line.Substring($line.IndexOf('{')).Trim()
    if ($jsonText.EndsWith(';')) {
        $jsonText = $jsonText.Substring(0, $jsonText.Length - 1)
    }

    $metadata = $jsonText | ConvertFrom-Json

    [pscustomobject]@{
        Url                  = $url
        ProductId            = $metadata.productId
        Title                = $metadata.title
        ReleaseDateUtc       = $metadata.releaseDateUtc
        LastUpdateDateUtc    = $metadata.lastUpdateDateUtc
        PackageLastUpdateUtc = $metadata.packageLastUpdateDateUtc
        PublicVersion        = $metadata.version
        PackageFamilyNames   = (($metadata.packageFamilyNames | ForEach-Object { $_ }) -join ', ')
        InstallerType        = $metadata.installer.type
        InstallerId          = $metadata.installer.id
    }
}

function Get-ManifestSummary {
    param(
        [string]$Market = 'US'
    )

    $url = "https://storeedgefd.dsx.mp.microsoft.com/v9.0/packageManifests/{0}?Market={1}" -f $script:CodexStoreId, $Market
    $response = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
    $versionEntry = $response.Data.Versions | Select-Object -First 1
    $installer = $versionEntry.Installers | Select-Object -First 1

    [pscustomobject]@{
        Url                       = $url
        PackageIdentifier         = $response.Data.PackageIdentifier
        PackageVersion            = $versionEntry.PackageVersion
        Publisher                 = $versionEntry.DefaultLocale.Publisher
        PackageName               = $versionEntry.DefaultLocale.PackageName
        Architecture              = $installer.Architecture
        InstallerType             = $installer.InstallerType
        PackageFamilyName         = $installer.PackageFamilyName
        DownloadCommandProhibited = [bool]$installer.DownloadCommandProhibited
    }
}
