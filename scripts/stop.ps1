#requires -Version 5.1
<#
.SYNOPSIS
  Stop locally running FileForge backends.
  The mail subsystem is now served by the FastAPI app (:8000); there is no
  separate mail process.

.EXAMPLE
  scripts\stop.ps1                # stop server (:8000)
.EXAMPLE
  scripts\stop.ps1 -Ports 8000    # stop whatever listens on the given port(s)
#>
[CmdletBinding()]
param(
  [int[]]$Ports = @(8000)
)

$ErrorActionPreference = 'Stop'

foreach ($port in $Ports) {
  $owners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
  if ($owners) {
    foreach ($procId in $owners) {
      $name = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
      Write-Host "[stop] port ${port}: stopping PID $procId ($name)" -ForegroundColor Cyan
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
  } else {
    Write-Host "[stop] port ${port}: nothing listening" -ForegroundColor DarkGray
  }
}
