<#
.SYNOPSIS
    Builds the Windows installer, hashes it, and publishes it as a GitHub release.

.DESCRIPTION
    The updater in the app (`lib/services/update_service.dart`) asks GitHub for
    `releases/latest` of `abnmazin/StudyFlow-PDF` and downloads the `.exe`
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
      5. create the release `v<version>` in that repository,
      6. upload the installer as `StudyFlowPDF_Setup_<version>.exe`.

    Needs `GITHUB_TOKEN` with `contents: write` on the repository. `gh` is
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

.PARAMETER SkipDoc
    Publish the release but leave `app_config/installer` alone. Almost never what
    is wanted — the document is what the standalone downloader reads, and a
    release nobody is offered is invisible rather than broken. It exists for the
    case where the same version is being re-uploaded and the document already
    names it.

.EXAMPLE
    $env:GITHUB_TOKEN = 'ghp_...'
    .\tools\publish_release.ps1 -Notes '<the Arabic note the reader will see>'

.NOTES
    `abnmazin/StudyFlow-PDF` is the source repository itself, and it is public: the
    app reads `releases/latest` from it with no token, and a token shipped inside a
    client is a token given away.

    The last step therefore also writes the Firestore document `app_config/installer`
    through tools\publish_installer_doc.mjs, which finds the service account key on
    its own. It needs `node` and, for the Firestore write, that key — the same one
    tools\create_admin.mjs takes with --key.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Notes = '',
    [switch]$SkipBuild,
    [switch]$SkipDoc
)

$ErrorActionPreference = 'Stop'

# 5.1 negotiates TLS 1.0 on some machines; GitHub answers nothing below 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$owner = 'abnmazin'
$repo = 'StudyFlow-PDF'
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
# `curl.exe`, and not `Invoke-RestMethod`: on this machine the PowerShell 5.1 call
# hangs with its socket in CloseWait - GitHub closes the connection, HttpWebRequest
# never notices, and the script waits forever having created no release. That
# happened once, silently, after a successful build. curl answers `--max-time`
# instead, so a stall becomes an error.
$curl = 'curl.exe'
if (-not (Get-Command $curl -ErrorAction SilentlyContinue)) {
    throw 'curl.exe not found. It ships with Windows 10 and 11.'
}

$common = @(
    '-sS', '--max-time', '900',
    # Revocation is checked when it can be. Without this, curl on this machine dies
    # with CRYPT_E_NO_REVOCATION_CHECK: Windows Schannel cannot reach the CRL
    # distribution points, and it treats that as a failure rather than an unknown.
    # Best-effort keeps the check where it works and proceeds where it does not,
    # which is weaker than `-k` and much weaker than nothing.
    '--ssl-revoke-best-effort',
    '-H', "Authorization: Bearer $token",
    '-H', 'Accept: application/vnd.github+json',
    '-H', 'User-Agent: StudyFlow-PDF-Release-Script'
)

function Invoke-GitHub {
    param([string]$Url, [string[]]$Extra = @(), [string]$BodyFile)
    $out = New-TemporaryFile
    # Not `$args`: that name is PowerShell's own automatic array inside a function.
    $curlArgs = $common + $Extra
    if ($BodyFile) { $curlArgs += @('--data-binary', ('@"' + $BodyFile + '"')) }
    $code = & $curl @curlArgs '-o' $out.FullName '-w' '%{http_code}' $Url
    $body = Get-Content -Raw -Encoding UTF8 $out.FullName
    Remove-Item $out.FullName -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE for $Url`n$body" }
    if ([int]$code -ge 400) { throw "GitHub answered HTTP $code for $Url`n$body" }
    return ($body | ConvertFrom-Json)
}

$payload = @{
    tag_name   = $tag
    name       = "StudyFlow PDF $Version"
    body       = $Notes
    draft      = $false
    prerelease = $false
} | ConvertTo-Json

# A file, not a command-line argument: the notes are Arabic and the bytes have to
# go out as UTF-8. UTF-8 *without* a BOM, because a payload starting with one is
# not JSON any more.
$payloadFile = New-TemporaryFile
[System.IO.File]::WriteAllText($payloadFile.FullName, $payload,
    (New-Object System.Text.UTF8Encoding($false)))

try {
    $release = Invoke-GitHub -Url "https://api.github.com/repos/$owner/$repo/releases" `
        -Extra @('-X', 'POST', '-H', 'Content-Type: application/json; charset=utf-8') `
        -BodyFile $payloadFile.FullName
} catch {
    throw ("Could not create the release $tag. If it already exists, the version " +
           "was not bumped - delete that release, or publish the next version. " +
           $_.Exception.Message)
} finally {
    Remove-Item $payloadFile.FullName -Force -ErrorAction SilentlyContinue
}

# `uploads.` and not `api.`: the asset endpoint is a different host, and the name
# in the query is the name the app sees in the release.
$uploadUri = "https://uploads.github.com/repos/$owner/$repo/releases/$($release.id)/assets?name=$assetName"
$asset = Invoke-GitHub -Url $uploadUri `
    -Extra @('-X', 'POST', '-H', 'Content-Type: application/octet-stream') `
    -BodyFile $assetPath

Write-Host ''
Write-Host "Published: $($release.html_url)" -ForegroundColor Green
Write-Host "GitHub digest: $($asset.digest)" -ForegroundColor Green
if ($asset.digest -and $asset.digest -ne "sha256:$sha") {
    Write-Warning 'GitHub reports a different digest than the local hash.'
}
Write-Host 'The app checks that digest, so there is no second field to update.'

# -- the download document ---------------------------------------------------
# The standalone downloader does not read GitHub at all: it reads the Firestore
# document `app_config/installer` and takes the link from there. A release
# published without that document is a version no reader is offered, which is the
# exact trap recorded in docs/changelog.md under 2026-10-02 - `latest_version`
# and the link have to move together, in the same command.
#
# The node script finds the service account key by itself, so nothing has to be
# passed here that the caller would have to remember.

if ($SkipDoc) {
    Write-Host ''
    Write-Host '-SkipDoc: app_config/installer was not written.' -ForegroundColor Yellow
    return
}

$docScript = Join-Path $root 'tools\publish_installer_doc.mjs'
$notesFile = $null

# Computed before the try, because the catch block prints it as the command to run
# by hand — and a hint with an empty `--url` in it is no hint at all.
#
# `browser_download_url` is what GitHub reports for the asset just uploaded; the
# constructed form is the fallback for the day that field is missing.
$downloadUrl = $asset.browser_download_url
if (-not $downloadUrl) {
    $downloadUrl = "https://github.com/$owner/$repo/releases/download/$tag/$assetName"
}

try {
    Write-Host ''
    Write-Host 'Writing app_config/installer...' -ForegroundColor Cyan

    # A file, not an argument: the notes are Arabic, and PowerShell 5.1 hands a
    # command-line argument to node.exe as ANSI. Same reasoning as the release
    # payload above, and the same encoding.
    if ($Notes) {
        $notesFile = New-TemporaryFile
        [System.IO.File]::WriteAllText($notesFile.FullName, $Notes,
            (New-Object System.Text.UTF8Encoding($false)))
    }

    $docArgs = @(
        $docScript,
        '--version', $Version,
        '--url', $downloadUrl,
        '--page-url', $release.html_url,
        '--sha256', $sha,
        '--size', "$size"
    )
    if ($notesFile) { $docArgs += @('--notes-file', $notesFile.FullName) }

    & node @docArgs
    if ($LASTEXITCODE -ne 0) { throw "publish_installer_doc.mjs exited $LASTEXITCODE" }
} catch {
    # The release is already public by this point, so failing the whole script
    # would throw away a successful publish. The warning carries the command that
    # fixes it, because "the app offers an old version" is otherwise invisible.
    Write-Host ''
    Write-Warning @"
app_config/installer was not written. The release is published, but the
downloader and the in-app updater still point at the previous version.
Run this by hand:

  node tools\publish_installer_doc.mjs --version $Version `
    --url $downloadUrl --sha256 $sha --size $size

  $($_.Exception.Message)
"@
} finally {
    if ($notesFile) { Remove-Item $notesFile.FullName -Force -ErrorAction SilentlyContinue }
}


