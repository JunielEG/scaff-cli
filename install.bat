@echo off
setlocal

set "TOOL_NAME=scaff-cli"
set "REPO_URL=https://github.com/JunielEG/scaff-cli.git"
set "INSTALL_DIR=%USERPROFILE%\ScaffoldingTools\%TOOL_NAME%"

echo.
echo   %TOOL_NAME%  installer
echo   ----------------------------------------
echo.

if exist "%~dp0windows\scaffx.bat" (
    echo   source    ^ local files found
    set "SOURCE_DIR=%~dp0"
) else (
    echo   source    cloning from remote...
    git clone "%REPO_URL%" "%TEMP%\%TOOL_NAME%-install"
    if errorlevel 1 (
        echo   source    x clone failed
        pause & exit /b 1
    )
    set "SOURCE_DIR=%TEMP%\%TOOL_NAME%-install"
)

echo   install   %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

xcopy /E /I /Y  "%SOURCE_DIR%\templates"          "%INSTALL_DIR%\templates\" > nul
copy  /Y        "%SOURCE_DIR%\windows\scaffx.bat" "%INSTALL_DIR%\scaffx.bat" > nul
copy  /Y        "%SOURCE_DIR%\windows\scaffx.ps1" "%INSTALL_DIR%\scaffx.ps1" > nul

echo   files     ^ scaffx.bat, scaffx.ps1

rem -- verificacion post-copia de templates ------------------------------------
set "TMPL=%INSTALL_DIR%\templates"
set "COPY_OK=1"

rem si llega a annadir la logica de plantillas descomentar esta parte
rem if not exist "%TMPL%\files\"          ( echo   warn      ! templates\files\ no copiado    & set "COPY_OK=0" )
rem if not exist "%TMPL%\architectures\"  ( echo   warn      ! templates\architectures\ no copiado & set "COPY_OK=0" )
rem 
rem if "%COPY_OK%"=="1" (
rem     echo   templates ^ files\, architectures\
rem ) else (
rem     echo   templates x copia incompleta, verifica manualmente: %TMPL%
rem )

rem -- limpiar clone temporal --------------------------------------------------
if exist "%TEMP%\%TOOL_NAME%-install" rmdir /s /q "%TEMP%\%TOOL_NAME%-install"

rem -- PATH --------------------------------------------------------------------
for /f "skip=2 tokens=3*" %%A in (
    'reg query "HKCU\Environment" /v PATH 2^>nul'
) do set "CURRENT_PATH=%%A %%B"

echo %CURRENT_PATH% | findstr /i /c:"%INSTALL_DIR%" > nul
if errorlevel 1 (
    setx PATH "%CURRENT_PATH%;%INSTALL_DIR%" > nul
    echo   path      ^ added to user PATH
) else (
    echo   path      -  already present, skipping
)

echo.
if "%COPY_OK%"=="1" (
    echo   done.  run:  scaffx
) else (
    echo   done. advertencias.  revisa los warns arriba.
)
echo.
endlocal