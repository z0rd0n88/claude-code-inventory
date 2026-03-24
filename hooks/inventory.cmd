: << 'CMDBLOCK'
@echo off
"%ProgramFiles%\Git\bin\bash.exe" "%~dp0inventory.sh" %*
exit /b %ERRORLEVEL%
CMDBLOCK
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/inventory.sh" "$@"
