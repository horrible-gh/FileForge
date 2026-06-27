#requires -Version 5.1
<#
.SYNOPSIS
  [ABSORBED] The standalone MailAnchor server no longer exists.

.DESCRIPTION
  The mail server has been absorbed into the FileForge FastAPI backend as the
  "mail subsystem" (routes under /fileforge/mail/*, /fileforge/oauth/gmail).
  There is no separate Go backend (mailanchord) and no separate :8090 process
  anymore - mail-server\ is now pure Python and ships no .go sources or cmd\.

  This script is kept only so existing automation that still invokes
  scripts\run-mail-server.ps1 keeps working: it simply forwards to
  scripts\run-server.ps1, which starts the single uvicorn app (default
  http://localhost:8000) that already includes the mail subsystem.
#>
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ForwardArgs
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host '[run-mail-server] The MailAnchor backend was absorbed into the FileForge server.' -ForegroundColor Yellow
Write-Host '[run-mail-server] There is no separate Go (mailanchord) build or :8090 process anymore.' -ForegroundColor Yellow
Write-Host '[run-mail-server] Forwarding to run-server.ps1 - mail routes live at /fileforge/mail/* on the main app.' -ForegroundColor Cyan

& (Join-Path $ScriptDir 'run-server.ps1') @ForwardArgs
exit $LASTEXITCODE
