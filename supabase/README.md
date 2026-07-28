# Jpay Supabase migration

Supabase became the active Jpay application backend on 2026-07-28. Firebase is
retained as a rollback source and must not be deleted until the Supabase release
has passed its rollback window.

## Current migration status

The first normalized snapshot was imported and reconciled on 2026-07-28:

- 3 Auth users, created as confirmed accounts without passwords
- 1 of those accounts now has a directly assigned password with a verified
  public-client sign-in; the other 2 remain without passwords
- 3 profiles
- 2 groups and 12 group friends
- 45 expenses and 123 shares
- 108 paid shares
- 2 group totals and all 45 expense totals reconciled
- 1 legacy expense converted to the relational share structure
- no profile images copied because the Firebase Storage bucket returned HTTP
  404 and contained no accessible objects

The final pre-cutover snapshot produced the same aggregate counts. It was
reimported idempotently, every total passed again, and the directly assigned
password remained ready. A Supabase-enabled release APK was installed on the
connected Android device and launched to the new login screen without errors.

See [migration-report.md](migration-report.md) for the completed checks and
remaining cutover gates.

## Schema

The initial migration creates:

- `profiles`, linked to Supabase Auth
- `groups`, owned through `owner_id`
- `group_friends`, replacing the Firestore `friends` array
- `expenses`, replacing group expense subcollections
- `expense_shares`, replacing embedded `debts` arrays
- a private `profile-pictures` Storage bucket

Every imported record can retain its original Firestore ID in `firebase_id`.
Firebase user IDs are stored in `profiles.firebase_uid` because Supabase Auth
uses UUID primary keys.

Group totals are derived from unpaid shares by database triggers. Expense
creation, editing, payment and deletion use PostgreSQL functions so the expense,
shares and total remain consistent in a single transaction.

The follow-up verification migration asserts the expected RLS policy count,
client grants, Realtime publication, private Storage bucket, and RPC execution
permissions directly inside the remote database.

## Local and remote setup

1. Install the Supabase CLI and run `supabase init` if local containers are
   needed.
2. Link the intended project with `supabase link`.
3. Apply migrations with `supabase db push`.
4. Pass client credentials to Flutter with compile-time defines:

   ```powershell
   flutter run `
     --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
   ```

Never put a database password, service-role key, Firebase Admin private key or
Supabase secret key in the Flutter application.

## Data cutover

Completed:

1. Export Firebase Auth, profiles, groups, and expense subcollections.
2. Build the Firebase UID to Supabase UUID mapping in `profiles`.
3. Transform friend arrays and embedded debts into relational rows.
4. Convert paid timestamps and the legacy expense representation.
5. Import the snapshot and reconcile row counts and derived totals.
6. Switch the active Flutter runtime to Supabase Auth and the
   `SupabaseJpayRepository`.
7. Add Supabase-native group, profile, friend, expense, balance, settlement,
   and deletion flows.
8. Create and import a final checksummed Firebase snapshot.
9. Build and install the Supabase-enabled Android release.

Deferred for multi-user onboarding:

1. Configure custom SMTP before enabling password recovery or either dormant
   imported account.
2. Allow-list `com.example.jpay://reset-callback/` in the hosted Supabase Auth
   redirect settings. The Android and iOS app manifests already register it.
3. Implement and test the Supabase Auth recovery/update-password screen.
4. Replace debug release signing with a private production upload key.

When importing legacy paid shares without a `paidAt` value, assign the expense
date (or the migration timestamp when unavailable) so the relational paid-state
constraint remains valid.

The migration utilities are in `tools/migration`. Sensitive exports are kept
under its git-ignored `output/` directory.
