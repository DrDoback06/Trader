@echo off
REM One-click local runner for Trader on Windows.
REM Double-click this file, or run  .\run.bat  in PowerShell from the repo folder.
REM After the first successful setup it needs NO internet - it skips installing
REM whatever is already present and goes straight to running the app.
setlocal
cd /d "%~dp0"

echo ============================================================
echo   Trader - starting up
echo ============================================================
echo.

echo [1/3] Python environment...
if not exist ".venv\Scripts\python.exe" (
    py -3 -m venv .venv 2>nul || python -m venv .venv
)
if not exist ".venv\Scripts\python.exe" goto :no_python

REM Import the app the SAME way it launches below (backend on the path), so a flaky
REM editable install on a new pip never makes a working app look "broken".
set "PYTHONPATH=%CD%\backend"

REM If the app and its key libraries already import, skip the (network) install.
".venv\Scripts\python.exe" -c "import trader, sqlalchemy, apscheduler, fastapi, uvicorn" 2>nul
if not errorlevel 1 (
    echo   Packages already installed - skipping download.
    goto :catalogue
)
echo   Installing Python packages ^(needs internet the first time^)...
".venv\Scripts\python.exe" -m pip install --timeout 120 --retries 10 --upgrade pip
".venv\Scripts\python.exe" -m pip install --timeout 120 --retries 10 -e ".[dev]"
".venv\Scripts\python.exe" -c "import trader, sqlalchemy, apscheduler, fastapi, uvicorn" 2>nul
if not errorlevel 1 goto :catalogue
echo.
echo   Setup check failed. The real error is below ^(usually a missing package
echo   from a dropped download - just run run.bat again to resume^):
".venv\Scripts\python.exe" -c "import trader, sqlalchemy, apscheduler, fastapi, uvicorn"
goto :deps_failed

:catalogue
if /I "%~1"=="--catalogue" (
    echo.
    echo Importing the full Pokemon catalogue ^(needs internet; a few minutes^)...
    ".venv\Scripts\python.exe" -m trader.tools.import_pokemontcg
)

:frontend
echo.
echo [2/3] Building the dashboard...
where npm >nul 2>nul
if errorlevel 1 goto :no_node
pushd frontend
if not exist "node_modules" call npm install
call npm run build
popd

echo.
echo ============================================================
echo   [3/3] App is starting.
echo   Open this in your browser:   http://localhost:8000
echo   Leave THIS window open. Press Ctrl+C to stop the app.
echo ============================================================
echo.
".venv\Scripts\python.exe" -m uvicorn trader.main:app --app-dir backend --host 0.0.0.0 --port 8000
pause
exit /b 0

:no_python
echo.
echo  ERROR: could not create the Python environment. Is Python installed?
echo  Install Python 3.11+ from https://www.python.org/downloads/ , tick
echo  "Add Python to PATH", then open a NEW window and run run.bat again.
pause
exit /b 1

:no_node
echo.
echo  ERROR: Node.js / npm not found. Install the LTS from https://nodejs.org/ ,
echo  then open a NEW window and run run.bat again.
pause
exit /b 1

:deps_failed
echo.
echo  Setup did not complete. If the error above is a missing package, this is
echo  usually a dropped download on a flaky network: just run run.bat again to
echo  resume - each good download is cached - or do one run on a phone hotspot.
echo  Already-installed packages are kept.
pause
exit /b 1
