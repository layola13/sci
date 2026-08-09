@echo off
rem =================================================================
rem SCI installer / uninstaller for Windows (npm-style).
rem
rem   tools\install.bat                  build + install + add to PATH
rem   tools\install.bat uninstall         remove SCI from disk + PATH
rem   tools\install.bat --user           install into %LOCALAPPDATA%
rem                                      instead of %ProgramFiles%
rem
rem Layout installed:
rem   <prefix>\SCI\<version>\bin\sa.exe + LLVM-C.dll + hubproxy.exe...
rem   <prefix>\SCI\<version>\include\sa_std.h
rem   <prefix>\SCI\<version>\{demos,docs,README.md,AGENTS.md}
rem   <prefix>\SCI\current       (junction -> latest version)
rem   PATH gains <prefix>\SCI\current\bin
rem
rem <prefix> = %ProgramFiles% if admin, else %LOCALAPPDATA%\Programs
rem =================================================================
setlocal EnableDelayedExpansion

rem ---- Find repo root -------------------------------------------------
pushd "%~dp0.."
set "REPO=%CD%"
popd

rem ---- Parse args ----------------------------------------------------
set "MODE=install"
set "SCOPE=auto"
:argloop
if "%~1"=="" goto argdone
if /i "%~1"=="--user"  set "SCOPE=user" & shift & goto argloop
if /i "%~1"=="--admin" set "SCOPE=admin" & shift & goto argloop
if /i "%~1"=="uninstall" set "MODE=uninstall" & shift & goto argloop
if /i "%~1"=="--help" set "MODE=help" & shift & goto argloop
if /i "%~1"=="-h"     set "MODE=help" & shift & goto argloop
echo [install] unknown argument: %~1 >&2
exit /b 2
:argdone

if "%MODE%"=="help" goto :showhelp
goto :%MODE%

:showhelp
echo Usage:
echo   tools\install.bat              build + install + register PATH
echo   tools\install.bat --user       install per-user (no admin needed)
echo   tools\install.bat uninstall    remove SCI from disk and PATH
echo.
echo Environment overrides (optional):
echo   ZIG       full path to zig.exe     (default D:\zig-x86_64-windows-0.14.1\zig.exe)
echo   LLVM_INC  LLVM include dir        (default D:\LLVM-14.0.6\include)
echo   LLVM_LIB  LLVM lib dir            (default D:\LLVM-14.0.6\lib)
goto :eof

rem ====================================================================
rem  INSTALL
rem ====================================================================
:install

rem ---- Defaults for build ----
set "ZIG=%ZIG%"
if not defined ZIG set "ZIG=D:\zig-x86_64-windows-0.14.1\zig.exe"
set "LLVM_INC=%LLVM_INC%"
if not defined LLVM_INC set "LLVM_INC=D:\LLVM-14.0.6\include"
set "LLVM_LIB=%LLVM_LIB%"
if not defined LLVM_LIB set "LLVM_LIB=D:\LLVM-14.0.6\lib"
set "LLVM_BIN=%LLVM_LIB%\..\bin"

rem ---- Determine install scope/prefix ----
if /i "%SCOPE%"=="user" (
  set "PREFIX=%LOCALAPPDATA%\Programs"
  goto :prefix_done
)
if /i "%SCOPE%"=="admin" (
  set "PREFIX=%ProgramFiles%"
  goto :prefix_done
)
rem auto: prefer %ProgramFiles% only if we are elevated (admin).
net session >nul 2>&1
if %errorlevel%==0 (
  set "PREFIX=%ProgramFiles%"
) else (
  echo [install] not running elevated -- installing per-user under %LOCALAPPDATA%\Programs
  set "PREFIX=%LOCALAPPDATA%\Programs"
)
:prefix_done

set "SCI_BASE=%PREFIX%\SCI"

rem ---- Build SCI (LLVM-C backend) ----
echo == Building SCI (LLVM-C backend)
set "PATH=%LLVM_BIN%;%PATH%"
"%ZIG%" build install -Dllvm=true -Dllvm-include-dir="%LLVM_INC%" -Dllvm-lib-dir="%LLVM_LIB%" -Dllvm-lib-name=LLVM-C --summary all
if errorlevel 1 (
  echo [install] zig build install failed >&2
  exit /b 1
)

rem ---- Detect installed version from sa.exe ----
for /f "delims=" %%V in ('"%REPO%\zig-out\bin\sa.exe" --version') do set "SA_VER_RAW=%%V"
if not defined SA_VER_RAW (
  echo [install] could not read sa.exe --version >&2
  exit /b 1
)
set "SA_VER_RAW=%SA_VER_RAW:"=%"
for /f "tokens=1,2 delims= " %%a in ("%SA_VER_RAW%") do set "SA_VER=%%b"
if not defined SA_VER set "SA_VER=unknown"
echo [install] detected sa version: %SA_VER%

set "DEST=%SCI_BASE%\%SA_VER%"
echo == Installing to "%DEST%"
if exist "%DEST%" rmdir /s /q "%DEST%"
mkdir "%DEST%\bin" 2>nul
mkdir "%DEST%\include" 2>nul

copy /y "%REPO%\zig-out\bin\sa.exe"     "%DEST%\bin\" >nul
copy /y "%REPO%\zig-out\bin\sa.pdb"     "%DEST%\bin\" >nul
copy /y "%REPO%\zig-out\bin\LLVM-C.dll" "%DEST%\bin\" >nul
if exist "%REPO%\zig-out\bin\hubproxy.exe" copy /y "%REPO%\zig-out\bin\hubproxy.exe" "%DEST%\bin\" >nul
if exist "%REPO%\zig-out\bin\hubproxy.pdb" copy /y "%REPO%\zig-out\bin\hubproxy.pdb" "%DEST%\bin\" >nul
if exist "%REPO%\zig-out\include\sa_std.h" copy /y "%REPO%\zig-out\include\sa_std.h" "%DEST%\include\" >nul

mkdir "%DEST%\demos" 2>nul
mkdir "%DEST%\docs"   2>nul
xcopy /e /i /q /y "%REPO%\demos" "%DEST%\demos" >nul
xcopy /e /i /q /y "%REPO%\docs"  "%DEST%\docs"  >nul
if exist "%REPO%\README.md" copy /y "%REPO%\README.md" "%DEST%\" >nul
if exist "%REPO%\AGENTS.md" copy /y "%REPO%\AGENTS.md" "%DEST%\" >nul

rem Strip demo build outputs from the installed tree.
if exist "%DEST%\demos" (
  pushd "%DEST%\demos"
  for /r %%F in (*.exe *.pdb *.obj *.bc *.out *.wasm *.dll) do if exist "%%F" del /q "%%F" 2>nul
  for /d %%D in (bin) do if exist "%%D" rmdir /s /q "%%D" 2>nul
  popd
)

rem ---- Point %SCI_BASE%\current at the freshly installed version ----
if exist "%SCI_BASE%\current" rmdir "%SCI_BASE%\current" 2>nul
mklink /J "%SCI_BASE%\current" "%DEST%" >nul
if errorlevel 1 (
  echo [install] mklink /J failed; falling back to copy of bin to %SCI_BASE%\current_bin
  mkdir "%SCI_BASE%\current" 2>nul
  xcopy /e /i /q /y "%DEST%\*" "%SCI_BASE%\current" >nul
)

rem ---- Add %SCI_BASE%\current\bin to PATH ----
echo == Registering PATH
if /i "%SCOPE%"=="user" (
  set "PATH_SCOPE=User"
) else if /i "%PREFIX%"=="%LOCALAPPDATA%\Programs" (
  set "PATH_SCOPE=User"
) else (
  set "PATH_SCOPE=Machine"
)
set "SCI_BIN=%SCI_BASE%\current\bin"
powershell -NoProfile -Command ^
  "$scope='%PATH_SCOPE%';" ^
  "$new='%SCI_BIN%';" ^
  "$old=[Environment]::GetEnvironmentVariable('Path', $scope);" ^
  "if ($null -eq $old) { $old = '' };" ^
  "$entries = $old -split ';' | Where-Object { $_ -ne '' };" ^
  "if ($entries -notcontains $new) {" ^
  "  $combined = (@($new) + $entries) -join ';';" ^
  "  [Environment]::SetEnvironmentVariable('Path', $combined, $scope);" ^
  "  Write-Host ('added to ' + $scope + ' PATH: ' + $new)" ^
  "} else {" ^
  "  Write-Host ('already in ' + $scope + ' PATH: ' + $new)" ^
  "}"

echo.
echo == Installed SCI %SA_VER% to "%DEST%"
echo    PATH scope: %PATH_SCOPE%
echo    Registered: %SCI_BASE%\current\bin
echo NOTE: open a *new* terminal, then run:  sa --version
goto :end

rem ====================================================================
rem  UNINSTALL
rem ====================================================================
:uninstall
set "F=%ProgramFiles%\SCI\current"
if not exist "%F%" set "F=%LOCALAPPDATA%\Programs\SCI\current"
if not exist "%F%" (
  echo [uninstall] no SCI install found.
  goto :end
)

rem Remove both SCI trees (both scopes, tolerant of missing).
if exist "%ProgramFiles%\SCI"            rmdir /s /q "%ProgramFiles%\SCI"            2>nul
if exist "%LOCALAPPDATA%\Programs\SCI"   rmdir /s /q "%LOCALAPPDATA%\Programs\SCI"   2>nul

rem Scrub SCI paths from both Machine and User PATH.
for %%S in (Machine User) do (
  powershell -NoProfile -Command ^
    "$scope='%%S';" ^
    "$old=[Environment]::GetEnvironmentVariable('Path', $scope);" ^
    "if ($null -eq $old) { $old = '' };" ^
    "$entries = $old -split ';' | Where-Object { $_ -ne '' -and $_ -notlike '*\SCI\current\bin' -and $_ -notlike '*\SCI\current_bin' };" ^
    "$clean = $entries -join ';';" ^
    "[Environment]::SetEnvironmentVariable('Path', $clean, $scope);" ^
    "Write-Host ('cleaned SCI from ' + $scope + ' PATH')"
)
echo == Uninstalled SCI.
echo NOTE: open a new terminal for the PATH change to take effect.
goto :end

:end
endlocal
