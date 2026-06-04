$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$javaRoot = Join-Path (Split-Path -Parent $root) 'java'
$sourceJar = Join-Path $javaRoot 'dist\r0rpc-relay-client.jar'
$targetDir = Join-Path $root 'lib'
$targetJar = Join-Path $targetDir 'r0rpc-relay-client.jar'

Push-Location $javaRoot
try {
    powershell -ExecutionPolicy Bypass -File .\build.ps1
} finally {
    Pop-Location
}

if (-not (Test-Path $sourceJar)) {
    throw "Missing jar: $sourceJar"
}

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Copy-Item -Force $sourceJar $targetJar
Write-Host "Synced $targetJar"
