#requires -Version 5.1
<#
.SYNOPSIS
  Build and run the MailAnchor Go backend (mailanchord, http://localhost:8090).
  Replaces the old mail-server\run.bat.

.DESCRIPTION
  Loads mail-server\.env (falls back to .env.sample), frees the listen port if a
  stale instance is holding it, rebuilds mailanchord.exe from source, and runs it.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$MailDir = Join-Path $Root 'mail-server'
Set-Location $MailDir

# --- Load environment (KEY=VALUE lines) into the process environment ---
$envFile = Join-Path $MailDir '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $MailDir '.env.sample' }
if (Test-Path $envFile) {
  Write-Host "[run-mail-server] loading env from $(Split-Path -Leaf $envFile)" -ForegroundColor Cyan
  foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $name = $t.Substring(0, $i).Trim()
    $val  = $t.Substring($i + 1).Trim()
    Set-Item -Path "Env:$name" -Value $val
  }
}

$addr = if ($env:MAILANCHOR_ADDR) { $env:MAILANCHOR_ADDR } else { ':8090' }
$port = [int]($addr -replace '.*:', '')
if (-not $port) { $port = 8090 }

# --- Free the port if a previous listener is still holding it ---
Write-Host '[run-mail-server] stopping any running mailanchord.exe...' -ForegroundColor Cyan
Get-Process mailanchord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

for ($i = 0; $i -lt 8; $i++) {
  $owner = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
           Select-Object -First 1 -ExpandProperty OwningProcess
  if (-not $owner) { break }
  Write-Host "[run-mail-server] port $port still held by PID $owner; stopping it... ($($i+1)/8)" -ForegroundColor Yellow
  Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
}

if (-not ($env:GOOGLE_CLIENT_ID -or $env:MAILANCHOR_OAUTH_GMAIL_CLIENT_ID)) {
  Write-Host '[run-mail-server] Gmail OAuth not configured - /accounts/oauth/authorize returns 503 (server still starts).' -ForegroundColor Yellow
}
if (-not $env:MAILANCHOR_SMTP_HOST) {
  Write-Host '[run-mail-server] SMTP relay not configured - Gmail OAuth send can still use XOAUTH2; non-OAuth/password send needs MAILANCHOR_SMTP_HOST.' -ForegroundColor Yellow
}

Write-Host '[run-mail-server] building mailanchord.exe...' -ForegroundColor Cyan
go build -o mailanchord.exe ./cmd/mailanchord
if ($LASTEXITCODE -ne 0) { Write-Host '[run-mail-server] BUILD FAILED - not started.' -ForegroundColor Red; exit 1 }

Write-Host "[run-mail-server] starting mailanchord.exe on $addr ..." -ForegroundColor Cyan
& (Join-Path $MailDir 'mailanchord.exe')
