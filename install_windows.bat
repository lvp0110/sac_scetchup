@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "FOUND=0"
for /d %%D in ("%APPDATA%\SketchUp\SketchUp 20*") do (
  if exist "%%D\SketchUp\Plugins" (
    if exist "%%D\SketchUp\Plugins\sac_ease_prep" rmdir /s /q "%%D\SketchUp\Plugins\sac_ease_prep"
    copy /Y "sac_ease_prep.rb" "%%D\SketchUp\Plugins\sac_ease_prep.rb" >nul
    xcopy "sac_ease_prep" "%%D\SketchUp\Plugins\sac_ease_prep\" /E /I /Y >nul
    echo Installed: %%D\SketchUp\Plugins
    set "FOUND=1"
  )
)
if "%FOUND%"=="0" (
  echo SketchUp 2019 or newer was not found.
  echo Install manually: Window - Extension Manager - Install Extension - dist\SAC_EASE.rbz
  exit /b 1
)
echo.
echo Restart SketchUp.
echo Button: View - Toolbars - SAC EASE
echo If SketchUp asks about an unsigned extension, allow it.
endlocal
