[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [string]$TestBasePath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Join-Path $PSScriptRoot '../source/runtime')
$core = Join-Path $repositoryRoot 'installer\Setup-BimCad.ps1'
if ([string]::IsNullOrWhiteSpace($TestBasePath)) {
    $TestBasePath = Join-Path ([IO.Path]::GetTempPath()) 'AutodeskMcpTests'
}
$testRoot = Join-Path $TestBasePath ("amcp-test-{0}" -f [Guid]::NewGuid().ToString('N'))
$installationRoot = Join-Path $testRoot 'installed'
$testLocalAppData = Join-Path $testRoot 'localappdata'
$testTemporaryRoot = Join-Path $testRoot 'temp'
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$expectedVersion = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Raw).Trim()

function Get-Sha256Hex {
    param([string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

$expectedHash = Get-Sha256Hex -Path $PackagePath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $installationRoot '.agents\skills\old'), (Join-Path $installationRoot 'skill-review'), (Join-Path $installationRoot 'team-candidates'), (Join-Path $installationRoot 'team-collection'), (Join-Path $installationRoot 'backups'), $testLocalAppData, $testTemporaryRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $installationRoot 'VERSION') -Value '1.0.0-beta.15' -Encoding ASCII
    foreach ($name in @('skill-review', 'team-candidates', 'team-collection', 'backups')) {
        Set-Content -LiteralPath (Join-Path $installationRoot "$name\preserve.txt") -Value $name -Encoding ASCII
    }

    $env:LOCALAPPDATA = $testLocalAppData
    $env:TEMP = $testTemporaryRoot
    $env:TMP = $testTemporaryRoot
    . $core -Action Status -RepositoryPath $installationRoot -ReleaseManifestUrl 'https://example.invalid/latest.json' -LibraryOnly
    $script:MockDownloadSource = (Resolve-Path -LiteralPath $PackagePath).Path
    $script:MockManifestBytes = [Text.Encoding]::UTF8.GetPreamble() + [Text.Encoding]::UTF8.GetBytes((([ordered]@{
        schema_version = 1
        version = " v$expectedVersion "
        download_url = 'https://example.invalid/release.zip'
        sha256 = " $expectedHash "
    } | ConvertTo-Json)))
    function global:Invoke-WebRequest {
        param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
        if ([string]::IsNullOrWhiteSpace($OutFile)) {
            return [pscustomobject]@{ StatusCode = 200; Content = [byte[]]$script:MockManifestBytes }
        }
        Copy-Item -LiteralPath $script:MockDownloadSource -Destination $OutFile -Force
        [pscustomobject]@{ StatusCode = 200; Content = [byte[]]@() }
    }

    $parsedManifest = Get-PublicReleaseManifest
    Assert-True ($parsedManifest.Version -eq $expectedVersion) 'A UTF-8 byte-array manifest did not produce the expected normalized version.'
    Assert-True ($parsedManifest.Sha256 -eq $expectedHash) 'A UTF-8 byte-array manifest did not produce the expected checksum.'
    Assert-True ((Compare-ConnectorVersion '1.0.0-beta.10' '1.0.0-beta.9') -gt 0) 'Numeric prerelease ordering is incorrect.'
    Assert-True ((Compare-ConnectorVersion '1.0.0' '1.0.0-beta.9') -gt 0) 'Stable-release ordering is incorrect.'

    $release = [pscustomobject]@{
        Version = $expectedVersion
        DownloadUrl = 'https://example.invalid/release.zip'
        Sha256 = $expectedHash
    }
    $installed = Install-PublicRelease -Release $release
    Assert-True ((Get-Content -LiteralPath (Join-Path $installed 'VERSION') -Raw).Trim() -eq $expectedVersion) 'Installed VERSION does not match the release.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installed '.agents\skills') -PathType Container) 'Approved skills were not installed.'
    foreach ($name in @('skill-review', 'team-candidates', 'team-collection', 'backups')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $installed "$name\preserve.txt") -PathType Leaf) "$name was not preserved."
    }
    $state = Get-Content -LiteralPath (Join-Path $testLocalAppData 'AutodeskMcpConnector\update-state.json') -Raw | ConvertFrom-Json
    Assert-True ($state.installed_version -eq $expectedVersion) 'Update state does not contain the installed release version.'
    Assert-True ($state.installed_sha256 -eq $expectedHash) 'Update state does not contain the verified SHA-256.'

    $badRelease = [pscustomobject]@{
        Version = $expectedVersion
        DownloadUrl = 'https://example.invalid/release.zip'
        Sha256 = ('0' * 64)
    }
    $rejected = $false
    try { $null = Install-PublicRelease -Release $badRelease }
    catch { $rejected = $_.Exception.Message -match 'checksum verification failed' }
    Assert-True $rejected 'A release with a wrong SHA-256 was not rejected.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $installed 'VERSION') -Raw).Trim() -eq $expectedVersion) 'Checksum rejection changed the installed runtime.'

    $script:Action = 'Update'
    function Get-PublicReleaseManifest {
        [pscustomobject]@{
            Version = '1.0.0-beta.8'
            DownloadUrl = 'https://example.invalid/release.zip'
            Sha256 = $expectedHash
        }
    }
    $resolved = Get-Repository
    Assert-True ($resolved -eq (Resolve-Path -LiteralPath $installationRoot).Path) 'A newer installed version did not keep the current installation.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $installationRoot 'VERSION') -Raw).Trim() -eq $expectedVersion) 'The updater downgraded a newer installed version.'

    Write-Output 'Public release update test passed: parsed byte-array JSON, verified install, preserved local folders, rejected a bad checksum, and prevented downgrade.'
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
