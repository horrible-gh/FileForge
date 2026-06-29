#requires -Version 5.1
<#
.SYNOPSIS
  FileForge — one-time setup (Windows).

.DESCRIPTION
  Prepares the components for local development:
    server\       FastAPI backend  (Python venv + dependencies + .env)
                  - also serves the absorbed mail subsystem at /fileforge/mail/*
    client\       Flutter client   (packages + config\prod.json)
  (mail-server\ is a non-operational legacy copy - no separate build/run; the
   mail-server target is a no-op kept only for automation compatibility.)

  COLLECTS the values needed to write server\.env (SECRET_KEY, DB, Redis, Gmail
  OAuth) by prompting for them, instead of copying a placeholder template.

  Finally GENERATES the root run launchers - run-server.ps1 (FastAPI, incl. the
  absorbed mail subsystem) and run-client.ps1 (Flutter web) - so the project can be started straight from
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

# B0001 / NR0003: the deployed web client's API base is compiled into the bundle
# from client\config\prod.json. Normalize a user-entered "domain" answer into a
# clean scheme://host[:port] origin (default scheme https, no trailing slash, and
# drop any pasted /fileforge[/mail] tail) so SERVER_URL/MAIL_SERVER_URL can be
# derived from a single question instead of each defaulting to localhost.
function Resolve-PublicBase([string]$Value) {
  $v = "$Value".Trim().TrimEnd('/')
  if (-not $v) { return '' }
  if ($v -notmatch '^[a-zA-Z][a-zA-Z0-9+.\-]*://') { $v = "https://$v" }
  $v = $v -replace '/fileforge(/mail)?/?$', ''
  return $v.TrimEnd('/')
}

# Return a human reason when a prod web API base is the B0001 trap, else $null.
# A deployed https page blocks a localhost/loopback or plaintext-http API base via
# CSP "connect-src 'self' https: wss:" (cross-origin plaintext http), so the login
# POST never leaves the browser (status=null) - exactly the B0001 failure.
function Get-UnsafeProdUrlReason([string]$Url) {
  if (-not $Url) { return $null }
  if ($Url -match '://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2)([:/]|$)') {
    return "points at localhost/loopback (each visitor's own machine, not your server)"
  }
  if ($Url -match '^http://') {
    return "uses plaintext http:// (a deployed https page blocks it via CSP connect-src 'self' https: wss:)"
  }
  return $null
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
    RedirectUri  = Read-Value  'GOOGLE_REDIRECT_URI'  'Gmail OAuth redirect URI'  'http://localhost:8000/fileforge/oauth/gmail/callback'
  }
  return $script:Gmail
}

# NR0003 D2: the standalone MailAnchor needed SMTP relay + SecretStore settings in
# its own mail-server\.env. After absorption the FileForge app reads per-account
# smtp_host from the DB and Gmail uses smtp.gmail.com over XOAUTH2, so
# MAILANCHOR_SMTP_* / MAILANCHOR_SECRET_ENCRYPTION_KEY have no consumer. The dead
# collectors (Get-Smtp / Get-MailSecretKey) that were never called have been removed.

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
  # R0001: the standalone MailAnchor backend has been absorbed into the FileForge
  # FastAPI server (server\routers\mail\*). There is no separate process to build
  # or run anymore. SMTP relay / Gmail OAuth / SecretStore settings now live in
  # server\.env. This step is retained as a no-op so existing automation that
  # passes -Target mail-server keeps working.
  Write-Info 'mail-server\ - absorbed into the FileForge server (no separate build); see Initialize-Server.'
}

function Initialize-Client {
  Write-Info 'client\ - Flutter client'
  if (-not (Test-Cmd flutter)) { Write-Warn 'Flutter SDK not found - skipping client. Install Flutter and re-run.'; return }
  Push-Location (Join-Path $Root 'client')
  try {
    if (Confirm-Configure 'config\prod.json' 'client\config\prod.json') {
      Write-Info 'collecting values for client\config\prod.json (this is the DEPLOYMENT build config)'
      if ($script:Interactive) {
        Write-Host ''
        Write-Info 'prod.json is compiled into the released web/app bundle, so the browser that'
        Write-Info 'loads the deployed app must be able to reach these URLs. They must be the'
        Write-Info 'PUBLIC https origin of your server (e.g. https://files.example.com) - NOT'
        Write-Info "localhost (that points at each visitor's own machine and is blocked by the"
        Write-Info "deploy CSP connect-src 'self' https: wss:, which makes login fail). [B0001]"
      }

      # Existing prod.json values seed the defaults when reconfiguring.
      $existing = $null
      if (Test-Path 'config\prod.json') {
        try { $existing = Get-Content -Raw 'config\prod.json' | ConvertFrom-Json } catch { $existing = $null }
      }

      # One question for the public origin/domain; SERVER_URL/MAIL_SERVER_URL derive
      # from it. An explicit $env:SERVER_URL still wins (build automation), as before.
      $serverUrl = [Environment]::GetEnvironmentVariable('SERVER_URL')
      $mailUrl   = [Environment]::GetEnvironmentVariable('MAIL_SERVER_URL')
      if (-not $serverUrl) {
        $baseDefault = ''
        if ($existing -and $existing.SERVER_URL) { $baseDefault = Resolve-PublicBase $existing.SERVER_URL }
        $base = Resolve-PublicBase (Read-Value 'PUBLIC_BASE_URL' 'Public server origin/domain (e.g. https://files.example.com)' $baseDefault)
        if (-not $base) {
          # Blank answer (or non-interactive with no preset): keep a working LOCAL-ONLY
          # build, but make the localhost trap explicit instead of silently baking it in.
          $base = 'http://localhost:8000'
          Write-Warn 'no public origin given - defaulting prod.json to http://localhost:8000 (LOCAL-ONLY).'
          Write-Warn 'A DEPLOYED web build with this value will fail login: the browser blocks'
          Write-Warn "cross-origin http://localhost via CSP connect-src 'self' https: wss:. [B0001]"
          Write-Warn 'Re-run setup and enter your public https domain before building for deploy.'
        }
        $serverUrl = "$base/fileforge"
        if (-not $mailUrl) { $mailUrl = "$base/fileforge/mail" }
      } elseif (-not $mailUrl) {
        $mailUrl = (Resolve-PublicBase $serverUrl) + '/fileforge/mail'
      }

      $shareDefault = if ($existing -and $existing.SHARE_BASE_URL) { "$($existing.SHARE_BASE_URL)" } else { 'http://localhost:3000' }
      $shareUrl  = Read-Value 'SHARE_BASE_URL' 'Public share base URL' $shareDefault

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

    # Surface the B0001 trap on the EFFECTIVE prod.json - whether we just wrote it or
    # kept an existing one (the deployed bundle was built from a kept localhost config).
    if (Test-Path 'config\prod.json') {
      $eff = $null
      try { $eff = Get-Content -Raw 'config\prod.json' | ConvertFrom-Json } catch { $eff = $null }
      if ($eff -and $eff.SERVER_URL) {
        $reason = Get-UnsafeProdUrlReason "$($eff.SERVER_URL)"
        if ($reason) {
          Write-Warn "prod SERVER_URL '$($eff.SERVER_URL)' $reason - a deployed login will fail (B0001)."
          Write-Warn 'OK only for local same-host testing. For deploy, re-run setup (or set'
          Write-Warn '$env:PUBLIC_BASE_URL=https://your.domain) and rebuild the client.'
        }
      }
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
# Start the FileForge server stack: FastAPI (:8000), which now also serves the
# absorbed mail subsystem at /fileforge/mail/* (R0001). Stop it with scripts\stop.ps1.
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
$serverArgs = @('-Port', "$ServerPort")
if ($NoReload) { $serverArgs += '-NoReload' }
Write-Host '[run-server] starting local server stack...' -ForegroundColor Cyan
Start-ServiceWindow 'FileForge FastAPI backend' $serverScript $serverArgs
Write-Host '[run-server] server window is running. Stop it with scripts\stop.ps1.' -ForegroundColor Cyan
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
Write-Info 'Next: start the stacks from the repo root: .\run-server.ps1 (FastAPI, incl. absorbed mail) and .\run-client.ps1 (Flutter web).'
Write-Info 'Note: the server needs a reachable Redis instance (see server\.env REDIS_HOST).'
