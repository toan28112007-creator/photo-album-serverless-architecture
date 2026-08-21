# Build the app-api Lambda deployment package.
# No third-party dependencies (boto3 is provided by the Lambda runtime),
# so this is just a straight zip of the handler.
# Run from repo root: powershell -ExecutionPolicy Bypass -File scripts/build-app-api.ps1

$ErrorActionPreference = "Stop"

$srcDir = "src/lambda/app-api"
$buildDir = "$srcDir/build"

Write-Host "Cleaning previous build..."
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

Write-Host "Zipping handler.py..."
$zipPath = "$buildDir/app-api.zip"
Compress-Archive -Path "$srcDir/handler.py" -DestinationPath $zipPath -Force

Write-Host "Done: $zipPath"
