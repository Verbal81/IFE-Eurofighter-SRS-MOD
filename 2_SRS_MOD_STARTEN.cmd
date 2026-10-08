@echo off
title IFE Eurofighter SRS MOD - SRS und Bridge starten
cd /d "%~dp0"
if not exist "%~dp0Programm\StartRadio.ps1" (
  echo Bitte das ZIP zuerst vollstaendig entpacken. Der Ordner Programm muss vorhanden sein.
  pause
  exit /b 1
)
set "EFSRS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "EFSRS_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%EFSRS_PS%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Programm\StartRadio.ps1"
if errorlevel 1 (
  echo.
  echo Vorgang abgebrochen. Bitte die angezeigte Meldung beachten.
  pause
  exit /b 1
)
exit /b 0
