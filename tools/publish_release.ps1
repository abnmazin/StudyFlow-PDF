<#
.SYNOPSIS
    Builds the Windows installer, hashes it, and publishes it as a GitHub release.

.DESCRIPTION
    The updater in the app (`lib/services/update_service.dart`) asks GitHub for
    `releases/latest` of `abnmazin/StudyFlow-PDF-Releases` and downloads the `.exe`
    attached to it. Nothing else in this project produces that asset, so this
    script is the other half of the update flow: without it, the app offers an
    update nobody can install.

    It is a script and not a CI job on purpose. The build needs the Flutter Windows
    toolchain and Inno Setup, and the person who writes the release note is the one
    who runs it.

    Steps, in order:
      1. the version, from `pubspec.yaml` (or `-Version`),
      2. `flutter build windows --release`,
      3. `ISCC /DAppVersion=<version> installer.iss` -> build\installer\*.exe,
      4. SHA-256 of the installer (printed; GitHub computes its own as well),
      5. create the release `v<version>` in the release repository,
      6. upload the installer as `StudyFlowPDF_Setup_<version>.exe`.

    Needs `GITHUB_TOKEN` with `contents: write` on the release repository. `gh` is
    not used: it is not installed on this machine, and the two REST calls below are
    the whole of it.

    This file is ASCII on purpose. PowerShell 5.1 reads a `.ps1` with no byte order
    mark as ANSI, so Arabic written here would arrive mangled; the Arabic the
    reader sees belongs in `-Notes`, which is passed on the command line.

.PARAMETER Version
    What to publish, e.g. `1.2.0`. Defaults to the `version:` line of
    `pubspec.yaml` with the `+build` part dropped: the tag is `v1.2.0`, and the
    build number is not part of what a reader is offered.

.PARAMETER Notes
    The release body, shown in the app as "what is new". Write it in Arabic - it is
    displayed to the reader as it is.

.PARAMETER SkipBuild
    Upload what is already in `build\installer` instead of building again: for
    re-uploading after a failed upload, without paying for a second build.

.EXAMPLE
    $env:GITHUB_TOKEN = 'ghp_...'
    .\tools\publish_release.ps1 -Notes '<the Arabic note the reader will see>'

.NOTES
    `abnmazin/StudyFlow-PDF-Releases` has to exist and be public: the app reads it
    with no token, and a token shipped inside a client is a token given away.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Notes = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# 5.1 negotiates TLS 1.0 on some machines; GitHub answers nothing below 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$owner = 'abnmazin'
$repo = 'StudyFlow-PDF-Releases'
$root = Split-Path -Parent $PSScriptRoot

$token = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "GITHUB_TOKEN is not set. It needs 'contents: write' on $owner/$repo."
}

$iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
    throw "Inno Setup 6 not found at '$iscc'. Install it, or fix this path."
}
# -- version ------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Version)) {
    $match = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)' |
        Select-Object -First 1
    if (-not $match) { throw 'No "version:" line in pubspec.yaml.' }
    # `1.1.0+3` -> `1.1.0`: the tag names the version, not the build.
    $Version = $match.Matches[0].Groups[1].Value.Split('+')[0]
}
$Version = $Version.Trim().TrimStart('v', 'V')
$tag = "v$Version"
$assetName = "StudyFlowPDF_Setup_$Version.exe"
$built = Join-Path $root 'build\installer\StudyFlowPDF_Setup.exe'
$assetPath = Join-Path $root "build\installer\$assetName"

Write-Host "Publishing $tag" -ForegroundColor Cyan

# -- build --------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host 'Building the Windows release...' -ForegroundColor Cyan
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows --release failed.' }

    Write-Host 'Compiling the installer...' -ForegroundColor Cyan
    # The version is passed in so the installer cannot carry a number of its own
    # and drift from the build it packages; installer.iss keeps a fallback for a
    # hand-run ISCC.
    & $iscc "/DAppVersion=$Version" (Join-Path $root 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw 'ISCC failed.' }
}

if (-not (Test-Path $built)) { throw "No installer at '$built'. Run without -SkipBuild." }

# The versioned copy is what gets uploaded, and what the file is called once the
# app has downloaded it (`UpdateService.installerFileName`). The plain name stays
# for the paths the docs and the habits already use.
Copy-Item -Path $built -Destination $assetPath -Force

$size = (Get-Item $assetPath).Length
$sha = (Get-FileHash -Path $assetPath -Algorithm SHA256).Hash.ToLower()
Write-Host ("Installer: {0} ({1:N1} MB)" -f $assetName, ($size / 1MB)) -ForegroundColor Green
Write-Host "SHA-256:   $sha" -ForegroundColor Green

# -- publish ------------------------------------------------------------------
$headers = @{
    Authorization = "Bearer $token"
    'User-Agent'  = 'StudyFlow-PDF-Release-Script'
    Accept        = 'application/vnd.github+json'
}

$payload = @{
    tag_name   = $tag
    name       = "StudyFlow PDF $Version"
    body       = $Notes
    draft      = $false
    prerelease = $false
} | ConvertTo-Json

try {
    $release = Invoke-RestMethod -Method Post -Headers $headers `
        -ContentType 'application/json' -Body $payload `
        -Uri "https://api.github.com/repos/$owner/$repo/releases"
} catch {
    throw ("Could not create the release $tag. If it already exists, the version " +
           "was not bumped - delete that release, or publish the next version. " +
           $_.Exception.Message)
}

# `uploads.` and not `api.`: the asset endpoint is a different host, and the name
# in the query is the name the app sees in the release.
$uploadUri = "https://uploads.github.com/repos/$owner/$repo/releases/$($release.id)/assets?name=$assetName"
$asset = Invoke-RestMethod -Method Post -Headers $headers `
    -ContentType 'application/octet-stream' -InFile $assetPath -Uri $uploadUri

Write-Host ''
Write-Host "Published: $($release.html_url)" -ForegroundColor Green
Write-Host "GitHub digest: $($asset.digest)" -ForegroundColor Green
if ($asset.digest -and $asset.digest -ne "sha256:$sha") {
    Write-Warning 'GitHub reports a different digest than the local hash.'
}
Write-Host 'The app checks that digest, so there is no second field to update.'

