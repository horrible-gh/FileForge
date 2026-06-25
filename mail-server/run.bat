@echo off
setlocal enabledelayedexpansion
cd /d %~dp0
set MAILANCHOR_ENV=development
set MAILANCHOR_ADDR=:8090
set MAILANCHOR_DB_PATH=./mailanchor.db
set ALLOWED_ORIGIN=http://localhost:3031,http://127.0.0.1:3031,http://localhost:4152,http://127.0.0.1:4152
set MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE=..\server\keys\jwt_public.pem
set MAILANCHOR_FILEFORGE_ISSUER=fileforge
set MAILANCHOR_FILEFORGE_AUDIENCE=mailanchor
set PORT=8090

rem === Gmail OAuth credentials (R0001 stage 5) ===
rem Fill these three in to enable Gmail OAuth. Leaving them blank ONLY makes
rem /api/v1/accounts/oauth/authorize return 503 "oauth not configured" — it does
rem NOT stop the server from starting. The values are read once at boot, so after
rem changing them re-run this script to restart with the new values.
rem set GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
rem set GOOGLE_CLIENT_SECRET=your-client-secret
rem set GOOGLE_REDIRECT_URI=http://localhost:8090/api/v1/accounts/oauth/callback

if "%GOOGLE_CLIENT_ID%%MAILANCHOR_OAUTH_GMAIL_CLIENT_ID%"=="" (
  echo [run.bat] Gmail OAuth is NOT configured. /api/v1/accounts/oauth/authorize will return 503 oauth not configured.
  echo [run.bat] Uncomment and fill GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REDIRECT_URI above to enable it.
)

echo [run.bat] Stopping any running mailanchord.exe...
taskkill /F /IM mailanchord.exe >nul 2>&1

rem Killing the process is asynchronous on Windows, and the previous server may also
rem have been started another way (e.g. `go run`) so the name-based kill above misses
rem it. Rebuilding/starting before the OS releases port %PORT% makes the new process
rem die with "bind: address already in use" — i.e. the server appears to "not start".
rem Wait until port %PORT% is actually free; if it is still held after a few seconds,
rem kill whatever PID owns the listener (covers non-mailanchord.exe listeners).
set /a TRIES=0
:waitport
netstat -ano | findstr ":%PORT% " | findstr LISTENING >nul 2>&1
if errorlevel 1 goto portfree
set /a TRIES+=1
if !TRIES! GEQ 8 (
  echo [run.bat] Port %PORT% still in use after waiting; forcing the listener to stop...
  for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":%PORT% " ^| findstr LISTENING') do taskkill /F /PID %%P >nul 2>&1
  timeout /t 1 /nobreak >nul
  goto portfree
)
echo [run.bat] Waiting for port %PORT% to be released... (!TRIES!/8)
timeout /t 1 /nobreak >nul
goto waitport
:portfree

echo [run.bat] Building mailanchord.exe from current source...
go build -o mailanchord.exe ./cmd/mailanchord
if errorlevel 1 (
  echo [run.bat] BUILD FAILED - server not started. Fix the error above and run again.
  pause
  exit /b 1
)

echo [run.bat] Build OK. Starting mailanchord.exe on %MAILANCHOR_ADDR% ...
mailanchord.exe
pause
