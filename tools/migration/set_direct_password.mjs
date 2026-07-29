import fs from 'node:fs/promises';

import { createClient } from '@supabase/supabase-js';

import {
  cleanString,
  fail,
  sanitizeError,
} from './migration_common.mjs';

const supabaseUrl = cleanString(process.env.SUPABASE_URL);
const supabaseSecretKey = cleanString(process.env.SUPABASE_SECRET_KEY);
const supabasePublishableKey = cleanString(
  process.env.SUPABASE_PUBLISHABLE_KEY,
);
const passwordFilePath = cleanString(
  process.env.SUPABASE_DIRECT_PASSWORD_FILE,
);

if (!supabaseUrl) fail('supabase-url-required');
if (!supabaseSecretKey) fail('supabase-secret-key-required');
if (!supabasePublishableKey) fail('supabase-publishable-key-required');
if (!passwordFilePath) fail('direct-password-file-required');

const adminClient = createClient(supabaseUrl, supabaseSecretKey, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});
const publicClient = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});

function parsePasswordFile(contents) {
  const values = new Map();
  for (const rawLine of contents.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator <= 0) fail('direct-password-file-invalid');

    const key = line.slice(0, separator).trim().toLocaleLowerCase('en-US');
    const value = line.slice(separator + 1).trim();
    if (values.has(key)) fail('direct-password-file-duplicate-key');
    values.set(key, value);
  }

  const allowedKeys = new Set(['email', 'password']);
  for (const key of values.keys()) {
    if (!allowedKeys.has(key)) fail('direct-password-file-unknown-key');
  }

  const email = cleanString(values.get('email')).toLocaleLowerCase('en-US');
  const password = values.get('password') ?? '';
  if (!email || !email.includes('@')) fail('direct-password-email-invalid');
  if (password.length < 6) fail('direct-password-too-short');
  return { email, password };
}

async function listUsers() {
  const users = [];
  const perPage = 1000;
  for (let page = 1; ; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage,
    });
    if (error) fail(error.code ?? 'supabase-list-users-failed');
    users.push(...data.users);
    if (data.users.length < perPage) break;
  }
  return users;
}

try {
  const contents = await fs.readFile(passwordFilePath, { encoding: 'utf8' });
  const credentials = parsePasswordFile(contents);
  const users = await listUsers();
  const matches = users.filter(
    (user) =>
      cleanString(user.email).toLocaleLowerCase('en-US') ===
      credentials.email,
  );
  if (matches.length !== 1) fail('direct-password-user-match-not-unique');

  const user = matches[0];
  const { data: updated, error: updateError } =
    await adminClient.auth.admin.updateUserById(user.id, {
      password: credentials.password,
      email_confirm: true,
      app_metadata: {
        ...(user.app_metadata ?? {}),
        migration_password_ready: true,
      },
    });
  if (updateError) {
    fail(updateError.code ?? 'supabase-password-update-failed');
  }
  if (updated.user?.id !== user.id) fail('supabase-password-user-mismatch');

  const { data: session, error: signInError } =
    await publicClient.auth.signInWithPassword(credentials);
  if (signInError) {
    fail(signInError.code ?? 'supabase-password-sign-in-failed');
  }
  if (session.user?.id !== user.id || !session.session) {
    fail('supabase-password-session-mismatch');
  }
  const { error: signOutError } = await publicClient.auth.signOut();
  if (signOutError) {
    fail(signOutError.code ?? 'supabase-password-sign-out-failed');
  }

  console.log(
    JSON.stringify(
      {
        updatedUsers: 1,
        emailConfirmed: updated.user?.email_confirmed_at != null,
        signInVerified: true,
        signedOutAfterVerification: true,
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(
    JSON.stringify(sanitizeError(error, 'supabase-direct-password')),
  );
  process.exitCode = 1;
}

