#requires -Version 5.1
<#
.SYNOPSIS
  Run the Flutter client in Chrome for local development.
  Replaces the old run-app-chrome.bat / client\run-chrome-dev.bat.

.EXAMPLE
  scripts\run-client.ps1
.EXAMPLE
  scripts\run-client.ps1 -WebPort 4152 -Clean
.EXAMPLE
  scripts\run-client.ps1 -Config config\prod.json
#>
[CmdletBinding()]
param(
  [int]$WebPort = 3031,
  [string]$Config = 'config\dev.json',
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location (Join-Path $Root 'client')

if ($Clean) {
  Write-Host '[run-client] flutter clean' -ForegroundColor Cyan
  flutter clean
  flutter pub get
}

Write-Host "[run-client] flutter run -d chrome --web-port $WebPort ($Config)" -ForegroundColor Cyan
flutter run -d chrome --web-port $WebPort --dart-define-from-file=$Config
