Set-StrictMode -Version Latest

$script:CodexStoreId = '9PLM9XGG6VKS'
$script:CodexPackageName = 'OpenAI.Codex'
$script:CodexPackageFamilyName = 'OpenAI.Codex_2p2nqsd0c76g0'

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
    }
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
        [int]$MaxEventsPerLog = 400
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
            $events = Get-WinEvent -LogName $definition.LogName -MaxEvents $MaxEventsPerLog -ErrorAction Stop |
                Where-Object {
                    $_.TimeCreated -ge $start -and (
                        $_.Message -match 'OpenAI\.Codex' -or
                        $_.Message -match '9PLM9XGG6VKS'
                    )
                }

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

    $result | Sort-Object TimeCreated -Descending
}
