# Ride Fare Compare (Flutter)

Type any pickup and drop address, see estimated Uber, Ola and Rapido fares, tap Book to open that app.

## 1. Google Cloud setup
1. Create a project at https://console.cloud.google.com and turn on billing (there is a free monthly credit).
2. Enable these APIs: **Places API (New)** and **Routes API**.
   (Routes API is Google's replacement for the older Distance Matrix API.)
3. Create an API key. Restrict it to those two APIs, and later to your Android app package name.

## 2. Create the Flutter project
```
flutter create ride_compare
cd ride_compare
```
Copy `pubspec.yaml` and `lib/main.dart` from this folder over the new project's files, then:
```
flutter pub get
```

## 3. Android permissions
In `android/app/src/main/AndroidManifest.xml`, add above `<application>`:
```
<uses-permission android:name="android.permission.INTERNET"/>
```

## 4. Run
```
flutter run --dart-define=MAPS_KEY=YOUR_API_KEY
```

## Notes
- Fares are estimates. Edit the `rates` list in `lib/main.dart` to match real prices.
- Uber and Ola links fill in pickup and drop. Rapido has no public deep link, so it only opens Rapido.
- For a real release, keep the API key on your own server and call Google from there, so the key is not inside the app.
