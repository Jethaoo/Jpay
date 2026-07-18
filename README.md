# Jpay

Jpay is a Flutter app for tracking shared expenses and outstanding balances with
friends. It keeps each trip, household, or event in its own ledger and provides
a focused dark-mode interface for recording expenses, managing participants,
and marking payments as received.

<p align="center">
  <img src="assets/branding/jpay_app_icon_1024.png" alt="Jpay app icon" width="160">
</p>

## Features

- Email and password authentication with Firebase Authentication
- Dashboard showing outstanding balances and active ledgers
- Ledger creation, search, management, and deletion
- Per-ledger friend management
- Add and edit expenses with descriptions, tax, and service charges
- Track individual shares and paid or unpaid status
- Mark one debt or all debts for a friend as paid
- Profile display name and photo management
- iOS-inspired OLED dark theme with graphite surfaces and system-blue actions
- Platform icons for Android, iOS, macOS, web, and Windows

## Tech stack

- Flutter and Dart
- Material 3
- Firebase Authentication
- Cloud Firestore
- Cloud Storage for Firebase
- Google Fonts
- Image Picker

## Project structure

```text
lib/
├── app_theme.dart              # Shared dark theme and color palette
├── debt_calculations.dart      # Currency and outstanding-balance helpers
├── firebase_options.dart       # Generated FlutterFire configuration
├── group_details_screen.dart   # Balances, expenses, and friend management
├── main.dart                   # App entry point, authentication, and ledgers
└── profile_screen.dart         # Account and profile-photo management

firestore.rules                 # Firestore access rules
storage.rules                   # Profile-photo access rules
firebase.json                   # Firebase deployment configuration
```

## Requirements

- Flutter SDK compatible with Dart `^3.10.4`
- Android Studio or another Flutter-compatible editor
- A Firebase project
- Firebase CLI and FlutterFire CLI for configuring a new environment

Check the local setup with:

```bash
flutter doctor
flutter --version
```

## Firebase setup

The checked-in configuration currently targets the Firebase project
`jpay-17`. To use a different project, run:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

In Firebase Console, enable:

1. **Authentication** → Email/Password
2. **Cloud Firestore**
3. **Storage** for profile pictures

Cloud Storage must have a provisioned default bucket and the Firebase project
must use the Blaze plan before a new bucket can be created or accessed.
Without a bucket, profile-photo uploads fail with HTTP 404 even when the local
security rules are correct.

Associate the Firebase CLI with the project and deploy the rules:

```bash
firebase login
firebase use --add
firebase deploy --only firestore:rules,storage
```

The included Storage rules only accept authenticated image uploads at
`user_profile_pics/{uid}.jpg`, with a maximum file size of 5 MB.

## Run locally

Install dependencies and start the app:

```bash
flutter pub get
flutter run
```

To target a specific device:

```bash
flutter devices
flutter run -d <device-id>
```

## Quality checks

```bash
flutter analyze
flutter test
```

## Build Android APKs

Debug build:

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

Release build:

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

The current Android release configuration uses the debug signing key for local
installation and testing. Before publishing to Google Play, configure a private
upload keystore and replace the release signing configuration in
`android/app/build.gradle.kts`.

## Data access model

- Users can read and update only their own profile document.
- Users can create and access only ledgers they own.
- Expense documents inherit access from their parent ledger owner.
- Profile images are named after the authenticated user's UID.

Review and deploy `firestore.rules` and `storage.rules` whenever the data model
or upload behavior changes.
