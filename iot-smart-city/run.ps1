# Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

# Internal Windows helper. Use start_site.bat as the user-facing Windows entry point.
param(
  [string]$Input = "D:\iotdataback\IoTData\dataall",
  [string]$Db = "$PSScriptRoot\data\smart_city_iot.sqlite",
  [int]$Port = 5177,
  [switch]$Reimport
)

$ErrorActionPreference = "Stop"

$BundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$BundledNode = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"

if (!(Test-Path -LiteralPath $BundledPython)) {
  throw "Bundled Python was not found at $BundledPython"
}

if (!(Test-Path -LiteralPath $BundledNode)) {
  throw "Bundled Node.js was not found at $BundledNode"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Db) | Out-Null

if ($Reimport -or !(Test-Path -LiteralPath $Db)) {
  $importArgs = @(
    "$PSScriptRoot\scripts\import_iot_to_sqlite.py",
    "--input", $Input,
    "--output", $Db,
    "--replace"
  )
  & $BundledPython @importArgs
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

$env:IOT_DB = $Db
$env:PORT = "$Port"
& $BundledNode --no-warnings "$PSScriptRoot\server\server.mjs"
