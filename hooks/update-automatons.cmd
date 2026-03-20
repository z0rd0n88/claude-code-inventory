: << 'CMDBLOCK'
@echo off
"%ProgramFiles%\Git\bin\bash.exe" "%~dp0update-automatons.sh" %*
exit /b %ERRORLEVEL%
CMDBLOCK
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/update-automatons.sh" "$@"
