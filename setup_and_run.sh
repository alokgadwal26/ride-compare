#!/bin/bash
# Ride Fare Compare - one-command setup and run (Mac/Linux)
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "Flutter is not installed. Install it from flutter.dev first."; exit 1; }
read -p "Paste your Google API key and press Enter: " MAPS_KEY
cp lib/main.dart /tmp/main_backup.dart
[ -d android ] || flutter create --platforms=android --project-name ride_compare .
cp /tmp/main_backup.dart lib/main.dart
M=android/app/src/main/AndroidManifest.xml
grep -q "android.permission.INTERNET" $M || sed -i.bak 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' $M
flutter pub get
flutter run --dart-define=MAPS_KEY="$MAPS_KEY"
