#requires -Version 5.1
<#
.SYNOPSIS
  Stop locally running FileForge backends.
  Replaces the old server\stop.ps1 (now also covers the Go mail-server).

.EXAMPLE
  scripts\stop.ps1                # stop server (:8000) and mail-server (:8090)
.EXAMPLE
  scripts\stop.ps1 -Ports 8000    # stop whatever listens on the given port(s)
#>
[CmdletBinding()]
param(
  [int[]]$Ports = @(8000, 8090)
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
