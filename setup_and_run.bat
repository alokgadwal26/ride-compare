@echo off
REM Ride Fare Compare - one-click setup and run (Windows)
cd /d "%~dp0"
where flutter >nul 2>nul || (echo Flutter is not installed. Install it from flutter.dev first. & pause & exit /b 1)
set /p MAPS_KEY=Paste your Google API key and press Enter: 
copy /y lib\main.dart "%TEMP%\main_backup.dart" >nul
if not exist android call flutter create --platforms=android --project-name ride_compare .
copy /y "%TEMP%\main_backup.dart" lib\main.dart >nul
powershell -Command "$f='android\app\src\main\AndroidManifest.xml'; $t=Get-Content $f -Raw; if($t -notmatch 'android.permission.INTERNET'){ $t=$t -replace '<application','<uses-permission android:name=\"android.permission.INTERNET\"/>`n    <application'; Set-Content $f $t }"
call flutter pub get
call flutter run --dart-define=MAPS_KEY=%MAPS_KEY%
pause
