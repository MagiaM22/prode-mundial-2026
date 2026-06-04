@echo off
chcp 65001 >nul
title Prode Mundial 2026
echo.
echo  ============================================
echo    Prode Mundial 2026 - Iniciando servidor
echo  ============================================
echo.

:: 4. PowerShell nativo (siempre disponible en Windows)
echo  Usando PowerShell...
powershell -ExecutionPolicy Bypass -File "%~dp0servidor.ps1"

echo.
echo  El servidor se cerro. Presiona cualquier tecla para salir.
pause >nul
