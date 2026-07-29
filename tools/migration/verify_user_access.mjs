import fs from 'node:fs/promises';

import { createClient } from '@supabase/supabase-js';

import { cleanString, fail, sanitizeError } from './migration_common.mjs';

const supabaseUrl = cleanString(process.env.SUPABASE_URL);
const supabasePublishableKey = cleanString(
  process.env.SUPABASE_PUBLISHABLE_KEY,
);
const supabaseSecretKey = cleanString(process.env.SUPABASE_SECRET_KEY);
const passwordFilePath = cleanString(
  process.env.SUPABASE_DIRECT_PASSWORD_FILE,
);

if (!supabaseUrl) fail('supabase-url-required');
if (!supabasePublishableKey) fail('supabase-publishable-key-required');
if (!passwordFilePath && !supabaseSecretKey) {
  fail('user-access-credential-source-required');
}

const client = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});
const adminClient = supabaseSecretKey
  ? createClient(supabaseUrl, supabaseSecretKey, {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    })
  : null;

function parseCredentials(contents) {
  const values = new Map();
  for (const rawLine of contents.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator <= 0) fail('direct-password-file-invalid');
    values.set(
      line.slice(0, separator).trim().toLocaleLowerCase('en-US'),
      line.slice(separator + 1).trim(),
    );
  }
  const email = cleanString(values.get('email')).toLocaleLowerCase('en-US');
  const password = values.get('password') ?? '';
  if (!email || !password) fail('direct-password-credentials-missing');
  return { email, password };
}

async function checked(promise, code) {
  const result = await promise;
  if (result.error) fail(result.error.code ?? code);
  return result;
}

async function signInForVerification() {
  if (passwordFilePath) {
    try {
      const contents = await fs.readFile(passwordFilePath, {
        encoding: 'utf8',
      });
      return checked(
        client.auth.signInWithPassword(parseCredentials(contents)),
        'supabase-user-sign-in-failed',
      );
    } catch (error) {
      if (error?.code !== 'ENOENT' || adminClient == null) throw error;
    }
  }

  if (adminClient == null) fail('supabase-admin-client-required');
  const users = [];
  const perPage = 1000;
  for (let page = 1; ; page += 1) {
    const listed = await checked(
      adminClient.auth.admin.listUsers({ page, perPage }),
      'supabase-list-users-failed',
    );
    users.push(...listed.data.users);
    if (listed.data.users.length < perPage) break;
  }
  const readyUsers = users.filter(
    (user) => user.app_metadata?.migration_password_ready === true,
  );
  if (readyUsers.length !== 1 || !readyUsers[0].email) {
    fail('supabase-password-ready-user-match-not-unique');
  }

  const link = await checked(
    adminClient.auth.admin.generateLink({
      type: 'magiclink',
      email: readyUsers[0].email,
    }),
    'supabase-verification-link-failed',
  );
  const tokenHash = cleanString(link.data.properties?.hashed_token);
  if (!tokenHash) fail('supabase-verification-token-missing');
  return checked(
    client.auth.verifyOtp({ token_hash: tokenHash, type: 'magiclink' }),
    'supabase-verification-token-exchange-failed',
  );
}

try {
  const signIn = await signInForVerification();
  if (!signIn.data.session || !signIn.data.user) {
    fail('supabase-user-session-missing');
  }

  const profileResult = await checked(
    client.from('profiles').select('id'),
    'supabase-user-profile-read-failed',
  );
  const groupResult = await checked(
    client.from('groups').select('id'),
    'supabase-user-groups-read-failed',
  );
  const groupIds = groupResult.data.map((group) => group.id);
  const friendResult = groupIds.length === 0
    ? { data: [] }
    : await checked(
        client.from('group_friends').select('id').in('group_id', groupIds),
        'supabase-user-friends-read-failed',
      );
  const expenseResult = groupIds.length === 0
    ? { data: [] }
    : await checked(
        client.from('expenses').select('id').in('group_id', groupIds),
        'supabase-user-expenses-read-failed',
      );
  const shareResult = await checked(
    client.from('expense_shares').select('id'),
    'supabase-user-shares-read-failed',
  );

  if (profileResult.data.length !== 1) {
    fail('supabase-user-profile-count-invalid');
  }
  if (groupResult.data.length === 0) {
    fail('supabase-user-has-no-groups');
  }

  await checked(client.auth.signOut(), 'supabase-user-sign-out-failed');
  console.log(
    JSON.stringify(
      {
        signInVerified: true,
        profilesVisible: profileResult.data.length,
        groupsVisible: groupResult.data.length,
        friendsVisible: friendResult.data.length,
        expensesVisible: expenseResult.data.length,
        sharesVisible: shareResult.data.length,
        signedOutAfterVerification: true,
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(JSON.stringify(sanitizeError(error, 'supabase-user-access')));
  process.exitCode = 1;
}
