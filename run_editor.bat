@echo off
set GODOT_PATH=C:\distr\Godot_v4.7.2-stable_win64.exe
set PROJECT_PATH=%~dp0src

if not exist "%GODOT_PATH%" (
    echo Error: Godot executable not found at %GODOT_PATH%
    pause
    exit /b 1
)

echo Opening Godot Editor...
"%GODOT_PATH%" -e --path "%PROJECT_PATH%"
