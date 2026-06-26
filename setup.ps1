#requires -Version 5.1
<#
.SYNOPSIS
  FileForge — one-time setup (Windows).

.DESCRIPTION
  Prepares all three components for local development:
    server\       FastAPI backend  (Python venv + dependencies + .env)
    mail-server\  MailAnchor (Go)  (modules + .env + build)
    client\       Flutter client   (packages + config\prod.json)

  COLLECTS the values needed to write each .env (SECRET_KEY, DB, Redis, Gmail
  OAuth, MailAnchor SecretStore, SMTP relay) by prompting for them, instead of copying a placeholder template.

  Finally GENERATES the root run launchers - run-server.ps1 (FastAPI + MailAnchor)
  and run-client.ps1 (Flutter web) - so the project can be started straight from
  the repository root without opening scripts\. They are regenerated every run.

  When a .env / config already exists, an interactive run ASKS whether to
  reconfigure it (default: keep). Answer yes - or pass -Force - and the old file
  is backed up under backups\<timestamp>\<relative-path> before the prompts run.
  A non-interactive run keeps existing files untouched (idempotent / CI-safe).

.PARAMETER Target
  Which component to set up: all (default), server, mail-server, or client.

.PARAMETER NonInteractive
  Accept all defaults and never prompt (CI / unmanned). Pre-set any value via an
  environment variable of the same name (e.g. $env:GOOGLE_CLIENT_ID) to inject it.

.PARAMETER Force
  Reconfigure even when a .env / config already exists (the old file is backed up
  first under backups\<timestamp>). Without it, an interactive run asks before
  touching an existing file.

.PARAMETER LaunchersOnly
  Only (re)generate the root run-server.ps1 / run-client.ps1 launchers, then exit
  without running the (slow) component setup.

.EXAMPLE
  .\setup.ps1
.EXAMPLE
  .\setup.ps1 server
.EXAMPLE
  .\setup.ps1 -Force
.EXAMPLE
  .\setup.ps1 -NonInteractive
#>
[CmdletBinding()]
param(
  [ValidateSet('all', 'server', 'mail-server', 'client')]
  [string]$Target = 'all',
  [Alias('y', 'NoInput')]
  [switch]$NonInteractive,
  [switch]$Force,
  # Only (re)generate the root run-server.ps1 / run-client.ps1 launchers and exit;
  # skip the (slow) component setup. Handy for refreshing the launchers alone.
  [switch]$LaunchersOnly
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# A non-interactive host (CI / no console) can never answer prompts.
$script:Interactive = -not ($NonInteractive -or [Console]::IsInputRedirected)

function Write-Info($msg) { Write-Host "[setup] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[setup] $msg" -ForegroundColor Yellow }
function Test-Cmd($name)  { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

if (-not $script:Interactive) {
  Write-Info 'non-interactive mode - using defaults / pre-set environment values for every .env field.'
}

# Ask for a value. Honors a pre-set environment variable of the same name
# (skips the prompt), falls back to $Default when blank or non-interactive.
function Read-Value([string]$Name, [string]$Question, [string]$Default = '') {
  $preset = [Environment]::GetEnvironmentVariable($Name)
  if ($preset) { Write-Info "$Question -> using pre-set `$env:$Name"; return $preset }
  if (-not $script:Interactive) { return $Default }
  $suffix = if ($Default) { " [$Default]" } else { '' }
  $ans = Read-Host "  $Question$suffix"
  if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
  return $ans
}

# Ask for a secret (no echo). Honors a pre-set env var; blank otherwise.
function Read-Secret([string]$Name, [string]$Question) {
  $preset = [Environment]::GetEnvironmentVariable($Name)
  if ($preset) { Write-Info "$Question -> using pre-set `$env:$Name"; return $preset }
  if (-not $script:Interactive) { return '' }
  $sec = Read-Host "  $Question (input hidden, blank = none)" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function New-Secret {
  $bytes = New-Object 'byte[]' 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
}

# Copy an existing config to backups\<timestamp>\<relative-path> so
# reconfiguration never destroys the previous values or scatters .bak files.
function Backup-File([string]$Path) {
  $resolved = Resolve-Path -LiteralPath $Path
  $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
  $pathFull = $resolved.Path
  if (-not $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to back up a file outside the repository root: $pathFull"
  }
  $relative = $pathFull.Substring($rootFull.Length).TrimStart('\', '/')
  $backupRoot = Join-Path $Root ('backups\' + (Get-Date -Format 'yyyyMMddHHmmss'))
  $destination = Join-Path $backupRoot $relative
  $destinationDir = Split-Path -Parent $destination
  New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
  Copy-Item -LiteralPath $resolved.Path -Destination $destination
  Write-Info "backed up existing file -> $destination"
}
# Decide whether to (re)collect & write a config file. Returns $true to collect.
#   missing               -> collect
#   -Force                -> back up, then collect
#   non-interactive+exists-> keep (idempotent), skip prompts
#   interactive+exists    -> ASK; yes backs up & collects, no keeps
# This is what guarantees an interactive run still PROMPTS when a .env/config
# already exists instead of silently skipping every question.
function Confirm-Configure([string]$Path, [string]$Label) {
  if (-not (Test-Path $Path)) { return $true }
  if ($Force) { Write-Info "$Label exists - reconfiguring (-Force)"; Backup-File $Path; return $true }
  if (-not $script:Interactive) { Write-Info "$Label already exists - keeping it (non-interactive)"; return $false }
  $ans = Read-Host "  $Label already exists. Reconfigure it (re-enter all values)? [y/N]"
  if ($ans -match '^(y|Y|yes|YES)$') { Backup-File $Path; return $true }
  Write-Info "keeping existing $Label"
  return $false
}

# Gmail OAuth is shared by server\ and mail-server\. Collect once.
$script:Gmail = $null
function Get-Gmail {
  if ($script:Gmail) { return $script:Gmail }
  if ($script:Interactive) {
    Write-Host ''
    Write-Info 'Gmail OAuth (optional - leave blank to skip; /accounts/oauth/authorize then returns 503).'
  }
  $script:Gmail = [ordered]@{
    ClientId     = Read-Value  'GOOGLE_CLIENT_ID'     'Gmail OAuth client ID'     ''
    ClientSecret = Read-Secret 'GOOGLE_CLIENT_SECRET' 'Gmail OAuth client secret'
    RedirectUri  = Read-Value  'GOOGLE_REDIRECT_URI'  'Gmail OAuth redirect URI'  'http://localhost:8090/api/v1/accounts/oauth/callback'
  }
  return $script:Gmail
}

function Get-Smtp {
  if ($script:Interactive) {
    Write-Host ''
    Write-Info 'Outbound SMTP relay (optional for Gmail OAuth; required for non-OAuth/password account sending).'
  }
  return [ordered]@{
    Host     = Read-Value  'MAILANCHOR_SMTP_HOST'     'SMTP relay host'     ''
    Port     = Read-Value  'MAILANCHOR_SMTP_PORT'     'SMTP relay port'     '587'
    User     = Read-Value  'MAILANCHOR_SMTP_USER'     'SMTP relay username' ''
    Password = Read-Secret 'MAILANCHOR_SMTP_PASSWORD' 'SMTP relay password'
  }
}

function Get-MailSecretKey {
  $key = [Environment]::GetEnvironmentVariable('MAILANCHOR_SECRET_ENCRYPTION_KEY')
  if (-not $key) { $key = New-Secret }
  if ($script:Interactive) { $key = Read-Value 'MAILANCHOR_SECRET_ENCRYPTION_KEY' 'MailAnchor OAuth SecretStore encryption key' $key }
  return $key
}

function Initialize-Server {
  Write-Info 'server\ - FastAPI backend'
  Push-Location (Join-Path $Root 'server')
  try {
    $py = if (Test-Cmd python) { 'python' } elseif (Test-Cmd py) { 'py' } else { $null }
    if (-not $py) { throw 'Python 3.10+ not found on PATH. Install it and re-run.' }

    if (-not (Test-Path '.venv')) {
      Write-Info 'creating virtualenv (.venv)'
      & $py -m venv .venv
    }
    $venvPy = Join-Path '.venv' 'Scripts\python.exe'
    Write-Info 'installing Python dependencies'
    & $venvPy -m pip install --upgrade pip | Out-Null
    & $venvPy -m pip install -r requirements.txt

    if (Confirm-Configure '.env' 'server\.env') {
      Write-Info 'collecting values for server\.env'
      $secret = [Environment]::GetEnvironmentVariable('SECRET_KEY')
      if (-not $secret) { $secret = New-Secret }
      if ($script:Interactive) { $secret = Read-Value 'SECRET_KEY' 'App SECRET_KEY' $secret }

      $dbType = (Read-Value 'DB_TYPE' 'Database type (sqlite|mysql|postgresql)' 'sqlite').ToLower()
      $dbPath = ''; $dbHost = 'localhost'; $dbPort = '0'; $dbUser = ''; $dbPass = ''; $dbName = 'fileforge'
      if ($dbType -eq 'mysql' -or $dbType -eq 'postgresql') {
        $dbHost = Read-Value  'DB_HOST'     'DB host' 'localhost'
        $dbPort = Read-Value  'DB_PORT'     'DB port' $(if ($dbType -eq 'mysql') { '3306' } else { '5432' })
        $dbUser = Read-Value  'DB_USER'     'DB user' 'fileforge'
        $dbPass = Read-Secret 'DB_PASSWORD' 'DB password'
        $dbName = Read-Value  'DB_DATABASE' 'DB name' 'fileforge'
      } else {
        $dbType = 'sqlite'; $dbPath = './fileforge.db'
      }

      $redisHost = Read-Value  'REDIS_HOST'     'Redis host' 'localhost'
      $redisPort = Read-Value  'REDIS_PORT'     'Redis port' '6379'
      $redisPass = Read-Secret 'REDIS_PASSWORD' 'Redis password'

      $g = Get-Gmail
      Write-Info 'writing server\.env'
      @(
        'ALLOWED_ORIGIN=*'
        "SECRET_KEY=$secret"
        'ACCESS_TOKEN_EXPIRE_MINUTES=30'
        'CONTEXT=/fileforge'
        'JWT_KEYS_DIR=./keys'
        'JWT_ISSUER=fileforge'
        'JWT_AUDIENCE=mailanchor'
        "DB_TYPE=$dbType"
        "DB_PATH=$dbPath"
        "DB_HOST=$dbHost"
        "DB_PORT=$dbPort"
        "DB_USER=$dbUser"
        "DB_PASSWORD=$dbPass"
        "DB_DATABASE=$dbName"
        'DB_SCHEMA='
        'RATE_LIMIT_DEFAULT=1000/hour'
        'RATE_LIMIT_LOGIN=50/minute'
        'RATE_LIMIT_UPLOAD=1200/minute'
        'RATE_LIMIT_DOWNLOAD=1200/minute'
        "REDIS_HOST=$redisHost"
        "REDIS_PORT=$redisPort"
        'REDIS_DB=0'
        "REDIS_PASSWORD=$redisPass"
        'REDIS_SSL=false'
        "GOOGLE_CLIENT_ID=$($g.ClientId)"
        "GOOGLE_CLIENT_SECRET=$($g.ClientSecret)"
        "GOOGLE_REDIRECT_URI=$($g.RedirectUri)"
      ) | Set-Content -Path '.env' -Encoding ascii
    }
  } finally { Pop-Location }
}

function Initialize-MailServer {
  Write-Info 'mail-server\ - MailAnchor (Go)'
  if (-not (Test-Cmd go)) { Write-Warn 'Go toolchain not found - skipping mail-server. Install Go and re-run.'; return }
  Push-Location (Join-Path $Root 'mail-server')
  try {
    if (Confirm-Configure '.env' 'mail-server\.env') {
      Write-Info 'collecting values for mail-server\.env'
      $addr = Read-Value 'MAILANCHOR_ADDR' 'MailAnchor listen address' ':8090'
      $mailSecret = Get-MailSecretKey
      $smtp = Get-Smtp
      $g = Get-Gmail
      Write-Info 'writing mail-server\.env'
      @(
        'MAILANCHOR_ENV=development'
        "MAILANCHOR_ADDR=$addr"
        'MAILANCHOR_DB_PATH=./mailanchor.db'
        "MAILANCHOR_SECRET_ENCRYPTION_KEY=$mailSecret"
        'ALLOWED_ORIGIN=http://localhost:3031,http://127.0.0.1:3031,http://localhost:4152,http://127.0.0.1:4152'
        "MAILANCHOR_SMTP_HOST=$($smtp.Host)"
        "MAILANCHOR_SMTP_PORT=$($smtp.Port)"
        "MAILANCHOR_SMTP_USER=$($smtp.User)"
        "MAILANCHOR_SMTP_PASSWORD=$($smtp.Password)"
        'MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE=../server/keys/jwt_public.pem'
        'MAILANCHOR_FILEFORGE_ISSUER=fileforge'
        'MAILANCHOR_FILEFORGE_AUDIENCE=mailanchor'
        "GOOGLE_CLIENT_ID=$($g.ClientId)"
        "GOOGLE_CLIENT_SECRET=$($g.ClientSecret)"
        "GOOGLE_REDIRECT_URI=$($g.RedirectUri)"
      ) | Set-Content -Path '.env' -Encoding ascii
    }
    Write-Info 'downloading Go modules'
    go mod download
    Write-Info 'building mailanchord.exe'
    go build -o mailanchord.exe ./cmd/mailanchord
  } finally { Pop-Location }
}

function Initialize-Client {
  Write-Info 'client\ - Flutter client'
  if (-not (Test-Cmd flutter)) { Write-Warn 'Flutter SDK not found - skipping client. Install Flutter and re-run.'; return }
  Push-Location (Join-Path $Root 'client')
  try {
    if (Confirm-Configure 'config\prod.json' 'client\config\prod.json') {
      Write-Info 'collecting values for client\config\prod.json'
      $serverUrl = Read-Value 'SERVER_URL'      'FileForge server URL'  'http://localhost:8000/fileforge'
      $mailUrl   = Read-Value 'MAIL_SERVER_URL' 'MailAnchor server URL' 'http://localhost:8090/api/v1'
      $shareUrl  = Read-Value 'SHARE_BASE_URL'  'Public share base URL' 'http://localhost:3000'
      Write-Info 'writing client\config\prod.json'
      @{
        SERVER_URL      = $serverUrl
        MAIL_SERVER_URL = $mailUrl
        SHARE_BASE_URL  = $shareUrl
        LOG_LEVEL       = 'warn'
        LOG_CONSOLE     = 'false'
        LOG_FILE        = 'true'
      } | ConvertTo-Json | Set-Content -Path 'config\prod.json' -Encoding ascii
    }
    Write-Info 'fetching Flutter packages'
    flutter pub get
  } finally { Pop-Location }
}

# Generate the root-level run launchers so the user can start each stack straight
# from the repository root after setup, without opening scripts\ to decide what to
# run. Server and client get separate launchers (R0001: keep server/client split).
# Regenerated on every setup run; these files are git-ignored (build artifacts).
function Write-RunLaunchers {
  Write-Info 'generating root run launchers (run-server.ps1, run-client.ps1)'

  $serverLauncher = @'
#requires -Version 5.1
# === GENERATED BY setup.ps1 - DO NOT EDIT (regenerated on every setup run) ===
# Start the FileForge server stack: FastAPI (:8000) + MailAnchor Go (:8090),
# each in its own PowerShell window. Stop them with scripts\stop.ps1.
[CmdletBinding()]
param([int]$ServerPort = 8000, [switch]$NoReload)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
function Get-PowerShellHost {
  $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($pwsh) { return $pwsh.Source }
  $ps = Get-Command powershell.exe -ErrorAction SilentlyContinue
  if ($ps) { return $ps.Source }
  throw 'PowerShell executable not found on PATH.'
}
function Quote-Arg([string]$Value) {
  if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
  return $Value
}
function Start-ServiceWindow([string]$Name, [string]$ScriptPath, [string[]]$ExtraArgs = @()) {
  $ps = Get-PowerShellHost
  $rawArgs = @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ExtraArgs
  $argLine = ($rawArgs | ForEach-Object { Quote-Arg "$_" }) -join ' '
  $proc = Start-Process -FilePath $ps -ArgumentList $argLine -WorkingDirectory $Root -PassThru
  Write-Host "[run-server] started $Name in a new PowerShell window (PID $($proc.Id))" -ForegroundColor Cyan
}
$serverScript = Join-Path $Root 'scripts\run-server.ps1'
$mailScript   = Join-Path $Root 'scripts\run-mail-server.ps1'
$serverArgs = @('-Port', "$ServerPort")
if ($NoReload) { $serverArgs += '-NoReload' }
Write-Host '[run-server] starting local server stack...' -ForegroundColor Cyan
Start-ServiceWindow 'FileForge FastAPI backend' $serverScript $serverArgs
Start-ServiceWindow 'MailAnchor Go backend' $mailScript
Write-Host '[run-server] server windows are running. Stop them with scripts\stop.ps1.' -ForegroundColor Cyan
'@

  $clientLauncher = @'
#requires -Version 5.1
# === GENERATED BY setup.ps1 - DO NOT EDIT (regenerated on every setup run) ===
# Start the FileForge Flutter client (delegates to scripts\run-client.ps1).
[CmdletBinding()]
param([int]$WebPort = 3031, [string]$Config = 'config\dev.json', [switch]$Clean)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $Root 'scripts\run-client.ps1'
# Hashtable splat = named binding. (An array splat would bind '-WebPort' to the
# positional [int]$WebPort and fail with a string-to-Int32 conversion error.)
$forwardArgs = @{ WebPort = $WebPort; Config = $Config }
if ($Clean) { $forwardArgs['Clean'] = $true }
& $script @forwardArgs
exit $LASTEXITCODE
'@

  Set-Content -Path (Join-Path $Root 'run-server.ps1') -Value $serverLauncher -Encoding ascii
  Set-Content -Path (Join-Path $Root 'run-client.ps1') -Value $clientLauncher -Encoding ascii
  Write-Info 'wrote run-server.ps1 and run-client.ps1 to the repository root.'
}

# Launchers are generated first so they exist even if a later component step fails.
Write-RunLaunchers
if ($LaunchersOnly) {
  Write-Info 'root run launchers generated; skipping component setup (-LaunchersOnly).'
  return
}

switch ($Target) {
  'all'         { Initialize-Server; Initialize-MailServer; Initialize-Client }
  'server'      { Initialize-Server }
  'mail-server' { Initialize-MailServer }
  'client'      { Initialize-Client }
}

Write-Info 'done.'
Write-Info 'Next: start the stacks from the repo root: .\run-server.ps1 (FastAPI + MailAnchor) and .\run-client.ps1 (Flutter web).'
Write-Info 'Note: the server needs a reachable Redis instance (see server\.env REDIS_HOST).'
