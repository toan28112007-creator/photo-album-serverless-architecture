# Build the image-processor Lambda deployment package.
# Run from repo root: powershell -ExecutionPolicy Bypass -File scripts/build-image-processor.ps1

$ErrorActionPreference = "Stop"

$srcDir = "src/lambda/image-processor"
$buildDir = "$srcDir/build"
$stagingDir = "$buildDir/staging"

Write-Host "Cleaning previous build..."
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Write-Host "Installing dependencies (Pillow) into staging dir..."
# --platform/--only-binary force a Lambda-compatible (manylinux) wheel,
# since Pillow has C extensions and a Windows-built wheel will NOT run
# on Lambda's Linux runtime.
pip install `
  -r "$srcDir/requirements.txt" `
  -t $stagingDir `
  --platform manylinux2014_x86_64 `
  --python-version 3.12 `
  --only-binary=:all: `
  --implementation cp

Write-Host "Copying handler.py..."
Copy-Item "$srcDir/handler.py" -Destination $stagingDir

Write-Host "Zipping..."
$zipPath = "$buildDir/image-processor.zip"
Compress-Archive -Path "$stagingDir/*" -DestinationPath $zipPath -Force

Write-Host "Done: $zipPath"
