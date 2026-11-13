@echo off
setlocal EnableExtensions
title Origins AI Watcher Launcher

cd /d "%~dp0"

set "SCRIPT=%~dp0origins_ai_watcher.py"
set "REQ=%~dp0origins_ai_watcher_requirements.txt"
set "VENV_DIR=%~dp0.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
set "LOG_DIR="

echo.
echo ============================================================
echo                  ORIGINS AI WATCHER
echo ============================================================
echo.

if not exist "%SCRIPT%" (
    echo [ERROR] origins_ai_watcher.py was not found beside this BAT file.
    echo Put this BAT file and the Python script in the BO22 root folder.
    pause
    exit /b 1
)

if not exist "%REQ%" (
    echo [ERROR] origins_ai_watcher_requirements.txt was not found.
    pause
    exit /b 1
)

if not exist "%VENV_PY%" (
    echo [SETUP] Creating an isolated Python environment...
    py -3 --version >nul 2>&1
    if not errorlevel 1 (
        py -3 -m venv "%VENV_DIR%"
    ) else (
        python -m venv "%VENV_DIR%"
    )
    if errorlevel 1 (
        echo.
        echo [ERROR] Could not create the Python environment.
        echo Install Python 3.10 or newer from https://www.python.org/downloads/
        echo Make sure the Python launcher or python.exe is added to PATH.
        pause
        exit /b 1
    )
)

if not exist "%VENV_PY%" (
    echo [ERROR] The virtual-environment Python executable is missing.
    pause
    exit /b 1
)

"%VENV_PY%" -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python 3.10 or newer is required.
    pause
    exit /b 1
)

"%VENV_PY%" -c "import mss, PIL, pytesseract" >nul 2>&1
if errorlevel 1 (
    echo [SETUP] Installing watcher dependencies. This requires internet access...
    "%VENV_PY%" -m pip install --upgrade pip
    if errorlevel 1 (
        echo [ERROR] Could not update pip.
        pause
        exit /b 1
    )
    "%VENV_PY%" -m pip install -r "%REQ%"
    if errorlevel 1 (
        echo [ERROR] Dependency installation failed.
        pause
        exit /b 1
    )
)

rem Detect common Plutonium T6 log locations. The watcher scans subfolders too.
if defined LOCALAPPDATA (
    if exist "%LOCALAPPDATA%\Plutonium\storage\t6\logs\" (
        set "LOG_DIR=%LOCALAPPDATA%\Plutonium\storage\t6\logs"
    ) else if exist "%LOCALAPPDATA%\Plutonium\storage\t6\main\" (
        set "LOG_DIR=%LOCALAPPDATA%\Plutonium\storage\t6\main"
    ) else if exist "%LOCALAPPDATA%\Plutonium\storage\t6\" (
        set "LOG_DIR=%LOCALAPPDATA%\Plutonium\storage\t6"
    )
)

echo [OK] BO22 project: "%~dp0"
if defined LOG_DIR (
    echo [OK] Plutonium logs: "%LOG_DIR%"
) else (
    echo [INFO] No standard Plutonium log folder found.
    echo        You can select the correct folder inside the watcher.
)
echo.
echo Starting Origins AI Watcher...
echo Keep Plutonium open for screen monitoring.
echo.

if defined LOG_DIR (
    "%VENV_PY%" "%SCRIPT%" --project "%~dp0" --logs "%LOG_DIR%"
) else (
    "%VENV_PY%" "%SCRIPT%" --project "%~dp0"
)

if errorlevel 1 (
    echo.
    echo [ERROR] Origins AI Watcher exited with an error.
    pause
)

endlocal
