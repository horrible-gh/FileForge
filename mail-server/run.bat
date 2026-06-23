@echo off
setlocal
cd /d %~dp0
set MAILANCHOR_ENV=development
set MAILANCHOR_ADDR=:8090
set MAILANCHOR_DB_PATH=./mailanchor.db
for %%f in ("%~dp0*.exe") do "%%f"
pause
