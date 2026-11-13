@echo off
setlocal EnableExtensions
title Origins AI Watcher Launcher

rem Resolve the install directory without a trailing backslash.
rem A quoted Windows argument ending in backslash can escape its closing quote.
for %%I in ("%~dp0.") do set "APP_DIR=%%~fI"
cd /d "%APP_DIR%"

set "SCRIPT=%APP_DIR%\origins_ai_watcher.py"
set "REQ=%APP_DIR%\origins_ai_watcher_requirements.txt"
set "VENV_DIR=%APP_DIR%\.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
set "PROJECT_DIR=%APP_DIR%"
set "LOG_DIR="

rem If the watcher was extracted next to a folder named bo22, use that checkout.
if not exist "%PROJECT_DIR%\zm_bo2_bots.gsc" (
    if exist "%APP_DIR%\..\bo22\zm_bo2_bots.gsc" (
        for %%I in ("%APP_DIR%\..\bo22") do set "PROJECT_DIR=%%~fI"
    )
)

echo.
echo ============================================================
echo                  ORIGINS AI WATCHER
echo ============================================================
echo.

if not exist "%SCRIPT%" (
    echo [ERROR] origins_ai_watcher.py was not found beside this BAT file.
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

rem Detect common Plutonium T6 log locations.
if defined LOCALAPPDATA (
    if exist "%LOCALAPPDATA%\Plutonium\storage\t6\logs\" (
        set "LOG_DIR=%LOCALAPPDATA%\Plutonium\storage\t6\logs"
    ) else if exist "%LOCALAPPDATA%\Plutonium\storage\t6\main\" (
        set "LOG_DIR=%LOCALAPPDATA%\Plutonium\storage\t6\main"
    ) else if exist "%LOCALAPPDATA%\Plutonium\storage\t6\" (
        set "LOG_DIR=%LOCALAPPDATA%\Plutonium\storage\t6"
    )
)

echo [OK] Watcher folder: "%APP_DIR%"
echo [OK] BO22 project folder: "%PROJECT_DIR%"
if not exist "%PROJECT_DIR%\zm_bo2_bots.gsc" (
    echo [NOTE] The BO22 GSC source was not found in this folder.
    echo        In the app, click Browse next to BO22 project folder
    echo        and select your actual Tenslaster\bo22 repository folder.
)
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
    "%VENV_PY%" "%SCRIPT%" --project "%PROJECT_DIR%" --logs "%LOG_DIR%"
) else (
    "%VENV_PY%" "%SCRIPT%" --project "%PROJECT_DIR%"
)

if errorlevel 1 (
    echo.
    echo [ERROR] Origins AI Watcher exited with an error.
    pause
)

endlocal
