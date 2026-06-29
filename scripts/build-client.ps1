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

# B0001 / NR0003: a web release compiles SERVER_URL straight from $Config into the
# bundle. If that base is localhost/loopback or plaintext http, the deployed https
# page blocks it via CSP "connect-src 'self' https: wss:" and login fails silently
# (status=null). Warn at the exact moment the trap would be baked in.
if ($Target -eq 'web' -and (Test-Path $Config)) {
  try {
    $cfg = Get-Content -Raw $Config | ConvertFrom-Json
    $u = "$($cfg.SERVER_URL)"
    if ($u -match '://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2)([:/]|$)' -or $u -match '^http://') {
      Write-Host "[build-client] WARNING: $Config SERVER_URL='$u' is localhost/plaintext-http. A deployed web build will be blocked by CSP (connect-src 'self' https: wss:) and login will fail (B0001). Set a public https origin (re-run setup or edit $Config) before building for deploy." -ForegroundColor Yellow
    }
  } catch { }
}

Write-Host "[build-client] flutter build $Target --release ($Config)" -ForegroundColor Cyan
flutter build $Target --release --dart-define-from-file=$Config
