@echo off
REM One-click local runner for Trader on Windows.
REM Double-click this file, or run  .\run.bat  in PowerShell from the repo folder.
REM First run installs everything (a few minutes); later runs are fast.
setlocal
cd /d "%~dp0"

echo ============================================================
echo   Trader - starting up
echo   First run installs packages (a few minutes). Please wait.
echo ============================================================
echo.

echo [1/3] Python environment...
if not exist ".venv\Scripts\python.exe" (
    py -3 -m venv .venv 2>nul || python -m venv .venv
)
if not exist ".venv\Scripts\python.exe" (
    echo.
    echo  ERROR: could not create the Python environment.
    echo  Python is probably not installed, or not on PATH.
    echo  1^) Install Python 3.11+ from https://www.python.org/downloads/
    echo  2^) During setup, TICK "Add Python to PATH"
    echo  3^) Close this window, open a NEW one, run run.bat again
    echo.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" -m pip install --timeout 120 --retries 10 --upgrade pip
".venv\Scripts\python.exe" -m pip install --timeout 120 --retries 10 -e ".[dev]"
if errorlevel 1 (
    echo.
    echo  ERROR installing Python packages - see the message above.
    pause
    exit /b 1
)

echo.
echo [2/3] Building the dashboard...
where npm >nul 2>nul
if errorlevel 1 (
    echo.
    echo  ERROR: Node.js / npm not found.
    echo  Install the "LTS" version from https://nodejs.org/ , then
    echo  close this window, open a NEW one, and run run.bat again.
    echo.
    pause
    exit /b 1
)
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
