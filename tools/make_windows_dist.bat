@echo off
setlocal EnableDelayedExpansion
rem =================================================================
rem SCI Windows x64 distribution package builder.
rem Produces dist\SCI-windows-x64.zip containing sa.exe + LLVM-C.dll
rem + hubproxy.exe + sa_std.h + demos + docs + README + AGENTS.md so
rem a fresh machine can unzip and run sa.exe without a separate LLVM install.
rem
rem Usage:
rem   tools\make_windows_dist.bat
rem Optional env vars:
rem   ZIG        full path to zig.exe   (default D:\zig-x86_64-windows-0.14.1\zig.exe)
rem   LLVM_INC   LLVM include dir       (default D:\LLVM-14.0.6\include)
rem   LLVM_LIB   LLVM lib dir           (default D:\LLVM-14.0.6\lib)
rem   OUT_ZIP    output zip path        (default dist\SCI-windows-x64.zip)
rem   ADD_PATH   1 = also persist %REPO%\zig-out\bin to user PATH
rem =================================================================

set "ZIG=%ZIG%"
if not defined ZIG set "ZIG=D:\zig-x86_64-windows-0.14.1\zig.exe"
set "LLVM_INC=%LLVM_INC%"
if not defined LLVM_INC set "LLVM_INC=D:\LLVM-14.0.6\include"
set "LLVM_LIB=%LLVM_LIB%"
if not defined LLVM_LIB set "LLVM_LIB=D:\LLVM-14.0.6\lib"
set "LLVM_BIN=%LLVM_LIB%\..\bin"
set "OUT_ZIP=%OUT_ZIP%"
if not defined OUT_ZIP set "OUT_ZIP=dist\SCI-windows-x64.zip"

pushd "%~dp0.."
set "REPO=%CD%"

rem Put LLVM bin on PATH so the build runner can locate LLVM-C.dll
set "PATH=%LLVM_BIN%;%PATH%"

echo == Building SCI with LLVM-C backend (install)
"%ZIG%" build install -Dllvm=true -Dllvm-include-dir="%LLVM_INC%" -Dllvm-lib-dir="%LLVM_LIB%" -Dllvm-lib-name=LLVM-C --summary all
if errorlevel 1 (
  echo [dist] build install failed >&2
  exit /b 1
)

echo == Verifying sa.exe starts (LLVM-C.dll load)
"%REPO%\zig-out\bin\sa.exe" --version
if errorlevel 1 (
  echo [dist] sa.exe failed to start -- LLVM-C.dll missing >&2
  exit /b 1
)

rem Stage dist into a scratch directory so the zip layout is clean.
set "STAGE=%REPO%\.dist_stage"
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%\bin"
mkdir "%STAGE%\include"
mkdir "%STAGE%\demos"
mkdir "%STAGE%\docs"

echo == Staging binaries
copy /y "%REPO%\zig-out\bin\sa.exe"     "%STAGE%\bin\" >nul
copy /y "%REPO%\zig-out\bin\sa.pdb"     "%STAGE%\bin\" >nul
copy /y "%REPO%\zig-out\bin\LLVM-C.dll" "%STAGE%\bin\" >nul
if exist "%REPO%\zig-out\bin\hubproxy.exe" copy /y "%REPO%\zig-out\bin\hubproxy.exe" "%STAGE%\bin\" >nul
if exist "%REPO%\zig-out\bin\hubproxy.pdb" copy /y "%REPO%\zig-out\bin\hubproxy.pdb" "%STAGE%\bin\" >nul

echo == Staging headers + demos + docs + top-level docs
if exist "%REPO%\zig-out\include\sa_std.h" copy /y "%REPO%\zig-out\include\sa_std.h" "%STAGE%\include\" >nul
xcopy /e /i /q /y "%REPO%\demos" "%STAGE%\demos" >nul
xcopy /e /i /q /y "%REPO%\docs"  "%STAGE%\docs"  >nul
if exist "%REPO%\README.md"  copy /y "%REPO%\README.md"  "%STAGE%\" >nul
if exist "%REPO%\AGENTS.md"  copy /y "%REPO%\AGENTS.md"  "%STAGE%\" >nul

rem Strip staged demos of build outputs and stray junk.
if exist "%STAGE%\demos" (
  pushd "%STAGE%\demos"
  for /r %%F in (*.exe *.pdb *.obj *.bc *.out *.wasm *.dll) do if exist "%%F" del /q "%%F" 2>nul
  for /d %%D in (bin) do if exist "%%D" rmdir /s /q "%%D" 2>nul
  popd
)

rem Use PowerShell Compress-Archive for portability (no 7-zip dependency).
echo == Packing %OUT_ZIP%
if not exist "%REPO%\dist" mkdir "%REPO%\dist"
if exist "%REPO%\%OUT_ZIP%" del /q "%REPO%\%OUT_ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%REPO%\%OUT_ZIP%' -Force"
if errorlevel 1 (
  echo [dist] Compress-Archive failed >&2
  exit /b 1
)

dir "%REPO%\%OUT_ZIP%"

rem Optional: persist %REPO%\zig-out\bin to the per-user PATH.
if /i "%ADD_PATH%"=="1" (
  echo == Adding %REPO%\zig-out\bin to user PATH
  powershell -NoProfile -Command ^
    "$p=[Environment]::GetEnvironmentVariable('Path','User');" ^
    "$base='%REPO%\zig-out\bin';" ^
    "if ($p -notlike ('*'+$base+'*')) { [Environment]::SetEnvironmentVariable('Path', $p.TrimEnd(';')+';'+$base, 'User'); Write-Host ('added: ' + $base) } else { Write-Host ('already present: ' + $base) }"
  echo NOTE: open a new terminal for the PATH change to take effect.
)

rmdir /s /q "%STAGE%"
popd
echo == Done. Output: %OUT_ZIP%
endlocal
