#requires -Version 5.1
<#
.SYNOPSIS
  Run the FileForge FastAPI backend (http://localhost:8000) for local development.
  Replaces the old run-server.bat / server\run.bat.

.EXAMPLE
  scripts\run-server.ps1
.EXAMPLE
  scripts\run-server.ps1 -Port 9000 -NoReload
#>
[CmdletBinding()]
param(
  [string]$BindHost = '0.0.0.0',
  [int]$Port = 8000,
  [switch]$NoReload
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location (Join-Path $Root 'server')

$venvUvicorn = Join-Path '.venv' 'Scripts\uvicorn.exe'
$venvPython  = Join-Path '.venv' 'Scripts\python.exe'

$args = @('app:app', '--host', $BindHost, '--port', "$Port", '--workers', '1')
if (-not $NoReload) { $args += '--reload' }

Write-Host "[run-server] starting uvicorn on ${BindHost}:${Port}$(if(-not $NoReload){' --reload'})" -ForegroundColor Cyan

if (Test-Path $venvUvicorn) {
  & $venvUvicorn @args
} elseif (Test-Path $venvPython) {
  & $venvPython -m uvicorn @args
} else {
  Write-Host '[run-server] .venv not found - run .\setup.ps1 first (falling back to system uvicorn)' -ForegroundColor Yellow
  uvicorn @args
}
