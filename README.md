# Jpay

Jpay is a Flutter app for tracking shared expenses and outstanding balances
with friends. Each trip, household, or event has its own group, participants,
expenses, and payment history.

<p align="center">
  <img src="assets/branding/jpay_app_icon_1024.png" alt="Jpay app icon" width="160">
</p>

## Features

- Email and password authentication with Supabase Auth
- Group creation, search, renaming, management, and deletion
- Per-group friend management
- Custom participant amounts with an optional explicit equal split
- Add and edit expenses with notes, tax, and service charges
- Private receipt, invoice, product-photo, and screenshot proof (up to five)
- On-device Latin and Chinese receipt OCR with reviewed merchant, total, date,
  item, and searchable raw-text extraction
- Optional current, searched, or map-pinned transaction locations
- Preset and reusable custom expense categories
- Per-group merchant, date, category, location, proof, and receipt-text search
- OpenStreetMap-backed transaction map and place picker
- Track individual shares and paid or unpaid status
- Mark one share or all shares for a friend as paid
- Familiar month dashboard with compact group and outstanding summaries
- Collapsible outstanding balances and chronological expense history
- Profile display name and private profile-picture storage
- iOS-inspired OLED dark theme with graphite surfaces and system-blue actions

## Tech stack

- Flutter, Dart, and Material 3
- Supabase Auth
- Supabase Postgres with Row Level Security and Realtime
- Supabase Storage
- Google Fonts, Image Picker, and Connectivity Plus

## Project structure

```text
lib/
|-- app_theme.dart                       # Shared dark theme and palette
|-- backend/                             # Supabase models and repository
|-- debt_calculations.dart               # Currency and balance helpers
|-- main.dart                            # App entry point
|-- supabase_app.dart                    # Authentication and app shell
|-- supabase_home_screen.dart            # Group search and management
|-- supabase_group_details_screen.dart   # Expenses, friends, and balances
`-- supabase_profile_screen.dart         # Account and profile pictures

supabase/                                # Schema and migration records
tools/migration/                         # Secure migration utilities
```

The former Firebase screens and configuration remain temporarily as rollback
reference but are no longer initialized by the active app runtime.

## Requirements

- Flutter SDK compatible with Dart `^3.10.4`
- Android Studio or another Flutter-compatible editor
- A Supabase project and Supabase CLI

Check the local setup:

```powershell
flutter doctor
flutter --version
```

## Run locally

Install dependencies and pass the public Supabase project values at compile
time:

```powershell
flutter pub get
flutter run `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
```

Password recovery is implemented but hidden by default. Enable it only after
custom SMTP delivery is verified and
`com.example.jpay://reset-callback/` is allow-listed in the hosted Supabase
Auth redirect settings:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME `
  --dart-define=ENABLE_PASSWORD_RECOVERY=true `
  --dart-define=PASSWORD_RECOVERY_REDIRECT_URL=com.example.jpay://reset-callback/
```

The redirect define is optional and defaults to the registered Jpay mobile
scheme shown above.

Map service endpoints are configurable without a new build:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME `
  --dart-define=OSM_TILE_URL=https://tile.openstreetmap.org/{z}/{x}/{y}.png `
  --dart-define=NOMINATIM_BASE_URL=https://nominatim.openstreetmap.org `
  --dart-define="MAP_USER_AGENT=Jpay/1.0 (contact@example.com)"
```

Public OpenStreetMap tile and Nominatim services are best-effort community
infrastructure. Keep attribution visible, do not prefetch or offline-download
tiles, use explicit place searches, and configure hosted or self-managed
OSM-compatible endpoints before usage exceeds their public policies.

To target a specific device:

```powershell
flutter devices
flutter run -d <device-id> `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
```

Never put a database password, service-role key, Supabase secret key, Firebase
Admin private key, or user password in the Flutter application.

## Quality checks

```powershell
flutter analyze
flutter test
```

## Build Android APK

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

The current release configuration uses the debug signing key for local
installation and testing. Before Google Play distribution, configure a private
upload keystore in `android/app/build.gradle.kts`.

## Data access model

- Users can read and update only their own profile.
- Users can create and access only groups they own through Row Level Security.
- Friends, expenses, and shares inherit access from the parent group owner.
- Expense creation, editing, settlement, and deletion use transactional
  PostgreSQL functions.
- Profile images use a private bucket scoped to the authenticated user UUID.
- Expense proof images use a separate private bucket scoped to the owner UUID;
  only short-lived signed URLs are shown in the app.
- Receipt OCR runs on the Android device. Only user-reviewed OCR text and
  structured fields are stored for later search.

Apply the versioned files under `supabase/migrations/` whenever the schema or
access model changes.

## Firebase-to-Supabase migration

The final Firebase snapshot was imported and reconciled on 2026-07-28. The
installed Android release now uses Supabase Auth, Postgres, Realtime, and
Storage. Firebase remains available only as a rollback source until the
Supabase release passes its rollback window.

See [supabase/README.md](supabase/README.md) and
[supabase/migration-report.md](supabase/migration-report.md) for the schema,
aggregate reconciliation results, and remaining safeguards.
