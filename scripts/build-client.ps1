#requires -Version 5.1
<#
.SYNOPSIS
  Build a release Flutter client artifact.
  Replaces the old client\build-android.bat.

.EXAMPLE
  scripts\build-client.ps1               # android apk, config\prod.json
.EXAMPLE
  scripts\build-client.ps1 -Target web
#>
[CmdletBinding()]
param(
  [string]$Target = 'apk',
  [string]$Config = 'config\prod.json'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location (Join-Path $Root 'client')

if (-not (Test-Path $Config)) { $Config = 'config\dev.json' }

Write-Host "[build-client] flutter build $Target --release ($Config)" -ForegroundColor Cyan
flutter build $Target --release --dart-define-from-file=$Config
