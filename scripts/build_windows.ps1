# Build Windows release artifacts: msix installer + portable zip folder.
# Run as Admin PowerShell from repo root:  .\scripts\build_windows.ps1
# Prereqs: VS Desktop C++ workload + Developer Mode + flutter pub get.

$ErrorActionPreference = 'Stop'
$root = (Get-Item $PSScriptRoot).Parent.FullName
Push-Location $root

$flutterBin = 'D:\env\flutter\bin'
if (Test-Path -Path $flutterBin) {
  if ($env:PATH -notlike "*$flutterBin*") {
    $env:PATH = "$flutterBin;$env:PATH"
  }
}
if (-not $env:HTTP_PROXY) {
  $env:HTTP_PROXY = 'http://127.0.0.1:7890'
  $env:HTTPS_PROXY = 'http://127.0.0.1:7890'
}

$m = Select-String -Path pubspec.yaml -Pattern '^version:\s*([\d.]+)\+(\d+)'
$version = if ($m) { $m.Matches.Groups[1].Value } else { '1.0.0' }

Write-Host "==> Building Windows Release ($version)"
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

Write-Host '==> Creating msix installer'
flutter pub run msix:create
if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }

Write-Host '==> Packing portable zip'
$rel = 'build\windows\x64\runner\Release'
$zipName = "CFYXX-$version-portable.zip"
$zipPath = Join-Path $root $zipName
if (Test-Path -Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path ($rel + '\*') -DestinationPath $zipPath
$zipMB = [math]::Round((Get-Item -Path $zipPath).Length / 1MB, 2)
Write-Host "Portable: $zipPath ($zipMB MB)"

Write-Host '==> Done'
Write-Host "  msix : $rel\CFYXX.msix"
Write-Host "  zip  : $zipName"
Pop-Location
