# Jpay Firebase-to-Supabase migration report

Date: 2026-07-28

This report contains aggregate reconciliation results only. It intentionally
excludes user emails, display names, group names, expense descriptions,
balances, credentials, password material, and profile URLs.

## Completed

- Applied the versioned relational schema, Row Level Security policies,
  restricted function grants, private profile-picture bucket, Realtime
  publication, and deployment assertions.
- Created a checksummed, git-ignored Firebase snapshot.
- Created three confirmed Supabase Auth users without passwords. No recovery
  emails were sent.
- Assigned a password directly to one account through the server-only Auth
  Admin API, verified a real public-client sign-in, and immediately signed out
  the verification session. Two dormant imported accounts remain without
  passwords.
- Preserved Firebase UIDs in `profiles.firebase_uid`.
- Preserved group and expense document IDs in `firebase_id`.
- Converted Firestore friend arrays and embedded debt arrays to relational
  rows.
- Converted the single legacy expense to one expense share.
- Preserved all paid states and supplied a valid paid timestamp fallback where
  the legacy source did not have one.
- Switched the active Flutter runtime from Firebase to Supabase Auth,
  Postgres, Realtime, and Storage.
- Added Supabase-native group search and management, collapsed balances,
  friend management, custom-share expense add/edit, settlement, expense
  deletion, and profile flows.
- Created a final checksummed Firebase snapshot immediately before cutover. Its
  aggregate counts matched the first snapshot.
- Reimported the final snapshot idempotently and reconciled every row and
  derived total.
- Built and installed the Supabase-enabled Android release APK. The installed
  app launched to the new Supabase login without startup errors.
- Restored the familiar Jpay dashboard and group-detail visual hierarchy on
  top of the Supabase runtime, rebuilt the release, and verified the signed-in
  dashboard with live migrated data on the connected Android device.
- Generated a non-emailed one-time token for the password-ready account,
  exchanged it through the public client, and verified that Row Level Security
  exposed exactly 1 profile, 2 groups, 12 friends, 45 expenses, and 123 shares.
  The verification session was immediately signed out.

## Reconciliation

| Record | Firebase snapshot | Supabase | Result |
| --- | ---: | ---: | --- |
| Auth users | 3 | 3 | Pass |
| Profiles expected after Auth trigger | 3 | 3 | Pass |
| Groups | 2 | 2 | Pass |
| Group friends | 12 | 12 | Pass |
| Expenses | 45 | 45 | Pass |
| Expense shares | 123 | 123 | Pass |
| Paid shares | 108 | 108 | Pass |

All 45 expense totals equal the sum of their imported shares. Both group
outstanding totals equal the sum of their unpaid shares.

Firebase Storage returned HTTP 404 during the read-only audit. No profile image
objects were available to copy.

## Remaining safeguards

- Configure custom SMTP and test recovery delivery before activating either
  dormant account or exposing self-service password recovery. SMTP is deferred
  for the current single-user pilot.
- Allow-list `com.example.jpay://reset-callback/` in hosted Supabase Auth. The
  Android and iOS app manifests already register this mobile recovery deep
  link.
- The Supabase recovery and update-password screens are implemented behind
  `ENABLE_PASSWORD_RECOVERY`; enable them only after SMTP and redirect testing.
- Complete an interactive device smoke test of expense and friend mutations.
- Replace the debug release signing key before Google Play distribution.
- Keep Firebase available as a rollback source through the agreed rollback
  window.

## Installed Android artifact

- Path: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 54,452,359 bytes
- SHA-256:
  `DFF8DDD07006618FD5333BED3BAB166D249CF5E715C0DC2FFE07EAD7A8A7BF05`
