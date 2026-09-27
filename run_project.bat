@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Disaster Aware Routing - Project Launcher
color 0A

REM ============================================================
REM DISASTER AWARE ROUTING & EMERGENCY MANAGEMENT SYSTEM
REM ============================================================

set "PROJECT=A:\PYTHON PROJECT\ruthwik disaster management project"
set "BACKEND=A:\PYTHON PROJECT\ruthwik disaster management project\backend"
set "MOBILE=A:\PYTHON PROJECT\ruthwik disaster management project\mobile"

REM Confirmed virtual environment location
set "VENV=A:\PYTHON PROJECT\ruthwik disaster management project\.venv"

set "PYTHON=A:\PYTHON PROJECT\ruthwik disaster management project\.venv\Scripts\python.exe"
set "PIP=A:\PYTHON PROJECT\ruthwik disaster management project\.venv\Scripts\pip.exe"
set "ALEMBIC=A:\PYTHON PROJECT\ruthwik disaster management project\.venv\Scripts\alembic.exe"

set "FLUTTER=C:\flutter\flutter\bin\flutter.bat"
set "ADB=C:\flutter\flutter\bin\platform-tools\adb.exe"

set "DB_NAME=disaster_routing"
set "DB_USER=postgres"
set "DB_HOST=localhost"
set "DB_PORT=5432"

set "BACKEND_URL=http://127.0.0.1:8000"
set "HEALTH_URL=http://127.0.0.1:8000/health"

cls

echo.
echo ============================================================
echo     DISASTER AWARE ROUTING ^& EMERGENCY MANAGEMENT
echo ============================================================
echo.
echo Project:
echo %PROJECT%
echo.
echo ============================================================
echo.

REM ============================================================
REM [1/6] CHECK PROJECT
REM ============================================================

echo [1/6] Checking project files...
echo.

if not exist "%PROJECT%" (
echo.
echo ============================================================
echo                         ERROR
echo ============================================================
echo.
echo Project folder not found:
echo %PROJECT%
echo.
goto FAIL
)

if not exist "%BACKEND%" (
echo Backend folder not found:
echo %BACKEND%
goto FAIL
)

if not exist "%MOBILE%" (
echo Mobile folder not found:
echo %MOBILE%
goto FAIL
)

echo [OK] Project folder found.
echo [OK] Backend folder found.
echo [OK] Mobile folder found.
echo.

REM ============================================================
REM [2/6] CHECK VIRTUAL ENVIRONMENT
REM ============================================================

echo [2/6] Checking Python virtual environment...
echo.

if not exist "%VENV%" (
echo.
echo ============================================================
echo                         ERROR
echo ============================================================
echo.
echo Virtual environment folder not found:
echo %VENV%
echo.
goto FAIL
)

if not exist "%PYTHON%" (
echo.
echo ============================================================
echo                         ERROR
echo ============================================================
echo.
echo Python executable not found:
echo %PYTHON%
echo.
goto FAIL
)

echo [OK] Virtual environment found.
echo [OK] Python found.
echo.

"%PYTHON%" --version
echo.

REM ============================================================
REM [3/6] CHECK FLUTTER
REM ============================================================

echo [3/6] Checking Flutter...
echo.

if not exist "%FLUTTER%" (
echo.
echo ============================================================
echo                         WARNING
echo ============================================================
echo.
echo Flutter not found:
echo %FLUTTER%
echo.
echo Flutter will not be launched. You can still start it manually.
echo.
) else (
echo [OK] Flutter found.
call "%FLUTTER%" --version
echo.
)

REM ============================================================
REM [4/6] CHECK ANDROID ADB
REM ============================================================

echo [4/6] Checking Android ADB...
echo.

if not exist "%ADB%" (
echo.
echo [WARNING] ADB not found: %ADB%
echo.
) else (
echo [OK] ADB found.
echo.
)

REM ============================================================
REM [5/6] FLASK DEPENDENCIES
REM ============================================================

echo [5/6] Installing/checking backend dependencies...
echo.

cd /d "%BACKEND%"

"%PYTHON%" -m pip install -q -r requirements.txt

if errorlevel 1 (
echo.
echo [WARNING] Some backend dependencies may not have installed.
echo.
) else (
echo [OK] Backend dependencies ready.
echo.
)

REM ============================================================
REM [6/6] START FASTAPI
REM ============================================================

echo [6/6] Starting FastAPI backend...
echo.

cd /d "%PROJECT%"

echo Starting FastAPI in a new window...
echo.

start "DISASTER MANAGEMENT - FASTAPI" cmd /k "cd /d "%PROJECT%" && "%PYTHON%" -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload"

echo [OK] FastAPI startup command sent.
echo.

echo Waiting for FastAPI to start...
timeout /t 5 /nobreak >nul

echo.
echo Checking backend health...
echo.

curl -s "%HEALTH_URL%" >nul 2>&1

if errorlevel 1 (
echo.
echo [WARNING] Health endpoint could not be reached yet.
echo Check the FastAPI window for errors.
echo.
) else (
echo.
echo [OK] FastAPI backend is running.
echo.
)

REM ============================================================
REM FLUTTER DEPENDENCIES
REM ============================================================

echo Installing/checking Flutter dependencies...
echo.

cd /d "%MOBILE%"

call "%FLUTTER%" pub get

if errorlevel 1 (
echo.
echo [WARNING] Flutter dependency installation had issues.
echo.
) else (
echo.
echo [OK] Flutter dependencies ready.
echo.
)

REM ============================================================
REM SHOW FINAL INFORMATION
REM ============================================================

echo ============================================================
echo                  PROJECT READY
echo ============================================================
echo.
echo Backend:
echo     %BACKEND_URL%
echo.
echo API Documentation:
echo     %BACKEND_URL%/docs
echo.
echo Health:
echo     %HEALTH_URL%
echo.
echo Database:
echo     %DB_NAME%
echo.
echo ============================================================
echo.
echo Starting Flutter application...
echo ============================================================
echo.

if exist "%FLUTTER%" (
call "%FLUTTER%" devices
echo.
echo Launching Flutter...
echo.
call "%FLUTTER%" run
) else (
echo Flutter not found. Please start it manually or check the Flutter installation.
echo.
)

echo.
echo ============================================================
echo Flutter application closed.
echo ============================================================
echo.

set "PGPASSWORD="
pause
exit /b 0

:FAIL

echo.
echo ============================================================
echo                         FAILED
echo ============================================================
echo.
echo Project launcher stopped because an error occurred.
echo.
echo Please read the error shown above.
echo.
echo ============================================================
echo.

set "PGPASSWORD="
pause
exit /b 1
