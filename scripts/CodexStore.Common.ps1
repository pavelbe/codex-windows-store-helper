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
