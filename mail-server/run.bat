@echo off
setlocal
cd /d %~dp0
set MAILANCHOR_ENV=development
set MAILANCHOR_ADDR=:8090
set MAILANCHOR_DB_PATH=./mailanchor.db
set ALLOWED_ORIGIN=http://localhost:3031,http://127.0.0.1:3031

echo [run.bat] Stopping any running mailanchord.exe...
taskkill /F /IM mailanchord.exe >nul 2>&1

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
