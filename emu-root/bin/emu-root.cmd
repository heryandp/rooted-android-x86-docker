@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM emu-root.cmd - Rooted Android 12 Emulator Launcher for Windows
REM ============================================================================

if defined ANDROID_HOME (
    set "SDK=%ANDROID_HOME%"
) else if defined ANDROID_SDK_ROOT (
    set "SDK=%ANDROID_SDK_ROOT%"
) else (
    set "SDK=%LOCALAPPDATA%\Android\Sdk"
)

set "ANDROID_HOME=%SDK%"
if not defined ANDROID_AVD_HOME set "ANDROID_AVD_HOME=%USERPROFILE%\.android\avd"
if not defined EMU_ROOT_AVD set "EMU_ROOT_AVD=Pixel_7_API_31_Rooted"
set "AVD=%EMU_ROOT_AVD%"
set "ADB=%SDK%\platform-tools\adb.exe"
set "EMULATOR=%SDK%\emulator\emulator.exe"
set "BOOT_TIMEOUT=180"
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto after_args
if /I "%~1"=="-h" goto show_help
if /I "%~1"=="--help" goto show_help
if /I "%~1"=="--status" goto cmd_status
if /I "%~1"=="--stop" goto cmd_stop
if /I "%~1"=="--shell" goto cmd_shell
if /I "%~1"=="--root" goto cmd_root_shell
if /I "%~1"=="--avd" (
    if "%~2"=="" (
        echo [ERROR] --avd requires an AVD name.
        exit /b 1
    )
    set "AVD=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--headless" (
    set "EXTRA_ARGS=!EXTRA_ARGS! -no-window -no-audio"
    shift
    goto parse_args
)
if /I "%~1"=="--wipe" (
    set "EXTRA_ARGS=!EXTRA_ARGS! -wipe-data"
    shift
    goto parse_args
)
set "EXTRA_ARGS=!EXTRA_ARGS! %~1"
shift
goto parse_args

:after_args
if not exist "%ADB%" (
    echo [ERROR] adb.exe not found at "%ADB%".
    echo         Run install-windows.ps1 or set ANDROID_HOME.
    exit /b 1
)
if not exist "%EMULATOR%" (
    echo [ERROR] emulator.exe not found at "%EMULATOR%".
    echo         Run install-windows.ps1 or set ANDROID_HOME.
    exit /b 1
)

"%ADB%" devices | findstr /R "^emulator-.*device" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo Emulator is already running:
    "%ADB%" devices -l
    exit /b 0
)

for /d %%d in ("%TEMP%\AndroidEmulator\emu-crash-*") do rd /s /q "%%d" >nul 2>&1

echo Starting %AVD% (Android 12 Play Store + Magisk Root, Cold Boot)...
start "" "%EMULATOR%" -avd "%AVD%" -no-snapshot -no-metrics %EXTRA_ARGS%

echo Waiting for emulator to boot (timeout %BOOT_TIMEOUT%s)...
set /a ELAPSED=0
:wait_adb
"%ADB%" devices | findstr /R "^emulator-.*device" >nul 2>&1
if not %ERRORLEVEL%==0 (
    if !ELAPSED! GEQ %BOOT_TIMEOUT% (
        echo [ERROR] Timed out waiting for emulator ADB connection after %BOOT_TIMEOUT%s.
        exit /b 1
    )
    timeout /t 2 /nobreak >nul
    set /a ELAPSED+=2
    goto wait_adb
)

:wait_boot
set "BOOT="
for /f "delims=" %%i in ('"%ADB%" -e shell getprop sys.boot_completed 2^>nul') do set "BOOT=%%i"
if not "%BOOT%"=="1" (
    if !ELAPSED! GEQ %BOOT_TIMEOUT% (
        echo [ERROR] Timed out waiting for Android boot_completed after %BOOT_TIMEOUT%s.
        exit /b 1
    )
    timeout /t 2 /nobreak >nul
    set /a ELAPSED+=2
    goto wait_boot
)

"%ADB%" devices -l
echo Ready! Use "emu-root --root" or "adb -e shell su" for root shell, or open Magisk app inside Android.
exit /b 0

:cmd_status
if not exist "%ADB%" (
    echo [ERROR] adb.exe not found at "%ADB%".
    exit /b 1
)
echo ANDROID_HOME     : %SDK%
echo ANDROID_AVD_HOME : %ANDROID_AVD_HOME%
echo Default AVD      : %AVD%
echo.
"%ADB%" devices -l
exit /b 0

:cmd_stop
if not exist "%ADB%" (
    echo [ERROR] adb.exe not found at "%ADB%".
    exit /b 1
)
echo Stopping running Android emulator...
"%ADB%" -e emu kill >nul 2>&1
if %ERRORLEVEL%==0 (
    echo Emulator stop signal sent.
) else (
    echo No running emulator found.
)
exit /b 0

:cmd_shell
"%ADB%" -e shell
exit /b %ERRORLEVEL%

:cmd_root_shell
"%ADB%" -e shell su
exit /b %ERRORLEVEL%

:show_help
echo Usage: emu-root [OPTIONS] [EXTRA_EMULATOR_ARGS...]
echo.
echo Options:
echo   --avd ^<name^>    Use a custom AVD name (default: %AVD%)
echo   --headless      Start emulator without window/audio (-no-window -no-audio)
echo   --wipe          Wipe user data before booting (-wipe-data)
echo   --status        Show SDK paths and connected ADB devices
echo   --stop          Stop the currently running emulator
echo   --shell         Open an interactive ADB shell on the emulator
echo   --root          Open a Magisk root shell (adb -e shell su)
echo   -h, --help      Show this help message
echo.
echo Environment Variables:
echo   ANDROID_HOME      Path to Android SDK (default: %%LOCALAPPDATA%%\Android\Sdk)
echo   ANDROID_AVD_HOME  Path to AVD directory (default: %%USERPROFILE%%\.android\avd)
echo   EMU_ROOT_AVD      Default AVD name (default: Pixel_7_API_31_Rooted)
exit /b 0
