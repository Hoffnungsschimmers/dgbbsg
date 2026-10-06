param(
    [string]$Flutter = 'flutter',
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $workspace
try {
    if (-not $SkipBuild) {
        & $Flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    }
    $versionLine = Get-Content -LiteralPath (Join-Path $workspace 'pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
    $version = ($versionLine -replace '^version:\s*', '').Trim()
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stage = Join-Path $workspace "dist\CFNB-$version-$stamp"
    $build = Join-Path $workspace 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath (Join-Path $build 'cfnb_app.exe'))) { throw 'Release executable missing.' }
    # A unique staging directory preserves earlier packages and never removes
    # files from the build directory. Exclude unrelated MSIX installers.
    New-Item -ItemType Directory -Path $stage | Out-Null
    Get-ChildItem -LiteralPath $build | Where-Object { $_.Extension -ne '.msix' } | Copy-Item -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $workspace 'docs\RELEASE_NOTES.md') -Destination $stage
    $zip = Join-Path $workspace "CFNB-$version-windows-portable-$stamp.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    Set-Content -LiteralPath "$zip.sha256" -Value "$hash  $([IO.Path]::GetFileName($zip))" -Encoding ascii
    Write-Output $zip
} finally {
    Pop-Location
}
