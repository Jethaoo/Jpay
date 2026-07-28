# Jpay migration utilities

These scripts are for the one-time Firebase-to-Supabase migration. Generated
exports are written only under the ignored `output/` directory and must never
be committed.

Required environment variables:

- `FIREBASE_SERVICE_ACCOUNT_PATH`
- `FIREBASE_STORAGE_BUCKET`
- `SUPABASE_URL` for import scripts
- `SUPABASE_SECRET_KEY` for import scripts

Run the read-only structural audit:

```powershell
$env:FIREBASE_SERVICE_ACCOUNT_PATH = 'C:\secure\firebase-service.json'
$env:FIREBASE_STORAGE_BUCKET = 'PROJECT.firebasestorage.app'
npm run audit
```

Create a normalized export for the one-time-reset migration:

```powershell
$env:FIREBASE_SERVICE_ACCOUNT_PATH = 'C:\secure\firebase-service.json'
npm run export
```

The export command is intentionally fail-safe: it will not overwrite an
existing export. Move or securely remove the prior ignored `output/` directory
before creating a new snapshot.

Import the snapshot using a server-only Supabase secret key:

```powershell
$env:SUPABASE_URL = 'https://PROJECT.supabase.co'
$env:SUPABASE_SECRET_KEY = 'SERVER_ONLY_SECRET'
npm run import
```

The importer creates confirmed Supabase users without passwords. No migration
email is sent automatically. Each migrated user must use password recovery
after the application is cut over to Supabase Auth.

For a single-user pilot, an administrator can set one migrated account's
password directly from a local ignored secret file:

```powershell
$env:SUPABASE_URL = 'https://PROJECT.supabase.co'
$env:SUPABASE_SECRET_KEY = 'SERVER_ONLY_SECRET'
$env:SUPABASE_PUBLISHABLE_KEY = 'PUBLISHABLE_KEY'
$env:SUPABASE_DIRECT_PASSWORD_FILE = 'C:\secure\direct-password.txt'
npm run set-direct-password
```

The file must contain exactly `email=...` and `password=...`. The helper matches
exactly one Supabase user, sets the password, verifies a real public-client
sign-in, immediately signs out, and logs no identity or secret values.

Verify that the same account can read its migrated rows through the public
client and Row Level Security:

```powershell
npm run verify-user-access
```

If the direct-password file has already been securely removed, provide the
server-only key instead. The verifier selects the single account marked ready,
generates a non-emailed one-time token, exchanges it through the public client,
checks the visible RLS rows, and immediately signs out.

Scripts must not log emails, names, password hashes, salts, API keys, private
keys, profile URLs, expense descriptions, or monetary values.
