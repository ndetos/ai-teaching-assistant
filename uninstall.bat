@echo off
setlocal enabledelayedexpansion

echo.
echo 🗑️  ndetos AI Teaching Assistant - Uninstaller
echo ==========================================
echo.

:: ============================================================
:: STEP 1: Stop and remove containers
:: ============================================================
echo ➜ Removing AI Tutor...

if exist "%USERPROFILE%\ai-tutor" (
    cd /d "%USERPROFILE%\ai-tutor" 2>nul
    docker compose down -v 2>nul
)

:: ============================================================
:: STEP 2: Remove Docker images, volumes, networks
:: ============================================================
docker rmi ndetos/ai-tutor-sim:latest 2>nul
docker rmi ollama/ollama:latest 2>nul
docker rmi qwen2.5:1.5b 2>nul

for /f "tokens=*" %%i in ('docker volume ls -q ^| findstr "ollama ndetos ai-tutor"') do docker volume rm -f %%i 2>nul
for /f "tokens=*" %%i in ('docker network ls -q ^| findstr "ndetos ai-tutor"') do docker network rm %%i 2>nul

:: ============================================================
:: STEP 3: Remove files and shortcuts
:: ============================================================
rmdir /s /q "%USERPROFILE%\ai-tutor" 2>nul
del "%USERPROFILE%\Desktop\ai-tutor.desktop" 2>nul
del "%USERPROFILE%\Desktop\start-ai-tutor.bat" 2>nul

echo ✅ AI Tutor removed

:: ============================================================
:: STEP 4: Ask about Docker removal
:: ============================================================
docker --version >nul 2>&1
if %errorlevel% equ 0 (
    echo.
    echo Do you want to uninstall Docker too?
    echo   1) Yes, remove everything including Docker
    echo   2) No, keep Docker
    set /p choice="Enter choice (1 or 2): "
    
    if "!choice!"=="1" (
        echo.
        echo ➜ Removing Docker...
        echo.
        echo To uninstall Docker Desktop on Windows:
        echo   1. Open Control Panel → Programs and Features
        echo   2. Find "Docker Desktop" and click Uninstall
        echo   3. Remove Docker data: rmdir /s /q "%USERPROFILE%\AppData\Local\Docker"
        echo   4. Remove Docker settings: rmdir /s /q "%USERPROFILE%\.docker"
    ) else (
        echo.
        echo ℹ️  Keeping Docker installed
    )
)

echo.
echo ==========================================
echo ✅ Uninstall complete!
echo Thank you for trying the AI Teaching Assistant.
echo ==========================================
pause
