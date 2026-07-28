import fs from 'node:fs/promises';
import path from 'node:path';

import { createClient } from '@supabase/supabase-js';

import {
  EXPORT_VERSION,
  checksum,
  chunked,
  cleanString,
  fail,
  normalizedName,
  roundCurrency,
  sanitizeError,
  stableFriendId,
} from './migration_common.mjs';

const supabaseUrl = cleanString(process.env.SUPABASE_URL);
const supabaseSecretKey = cleanString(process.env.SUPABASE_SECRET_KEY);
const exportPath = path.resolve(
  process.env.FIREBASE_EXPORT_PATH ?? 'output/firebase-export.json',
);

if (!supabaseUrl) fail('supabase-url-required');
if (!supabaseSecretKey) fail('supabase-secret-key-required');

const supabase = createClient(supabaseUrl, supabaseSecretKey, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});

async function checked(promise, code) {
  const result = await promise;
  if (result.error) {
    fail(code, {
      causeCode: result.error.code,
      status: result.error.status,
    });
  }
  return result.data;
}

async function listSupabaseUsers() {
  const users = [];
  const perPage = 1000;
  for (let page = 1; ; page += 1) {
    const data = await checked(
      supabase.auth.admin.listUsers({ page, perPage }),
      'supabase-list-users-failed',
    );
    users.push(...data.users);
    if (data.users.length < perPage) break;
  }
  return users;
}

async function importAuthUsers(data) {
  const existingUsers = await listSupabaseUsers();
  const byFirebaseUid = new Map();
  const byEmail = new Map();
  for (const user of existingUsers) {
    const firebaseUid = cleanString(user.user_metadata?.firebase_uid);
    if (firebaseUid) byFirebaseUid.set(firebaseUid, user);
    const email = cleanString(user.email).toLocaleLowerCase('en-US');
    if (email) byEmail.set(email, user);
  }

  const mapping = new Map();
  let created = 0;
  let reused = 0;

  for (const firebaseUser of data.authUsers) {
    const existingByUid = byFirebaseUid.get(firebaseUser.firebaseUid);
    const existingByEmail = byEmail.get(firebaseUser.email);
    if (
      existingByUid &&
      existingByEmail &&
      existingByUid.id !== existingByEmail.id
    ) {
      fail('supabase-user-identity-conflict');
    }

    let user = existingByUid ?? existingByEmail;
    if (user) {
      const existingFirebaseUid = cleanString(
        user.user_metadata?.firebase_uid,
      );
      if (
        existingFirebaseUid &&
        existingFirebaseUid !== firebaseUser.firebaseUid
      ) {
        fail('supabase-email-already-mapped');
      }
      const updated = await checked(
        supabase.auth.admin.updateUserById(user.id, {
          email_confirm: true,
          user_metadata: {
            ...(user.user_metadata ?? {}),
            firebase_uid: firebaseUser.firebaseUid,
            display_name: firebaseUser.displayName,
          },
          app_metadata: {
            ...(user.app_metadata ?? {}),
            migration_source: 'firebase',
          },
          ban_duration: firebaseUser.disabled ? '876000h' : 'none',
        }),
        'supabase-update-user-failed',
      );
      user = updated.user;
      reused += 1;
    } else {
      const createdUser = await checked(
        supabase.auth.admin.createUser({
          email: firebaseUser.email,
          email_confirm: true,
          user_metadata: {
            firebase_uid: firebaseUser.firebaseUid,
            display_name: firebaseUser.displayName,
          },
          app_metadata: { migration_source: 'firebase' },
          ban_duration: firebaseUser.disabled ? '876000h' : 'none',
        }),
        'supabase-create-user-failed',
      );
      user = createdUser.user;
      created += 1;
    }
    if (!user?.id) fail('supabase-user-id-missing');
    mapping.set(firebaseUser.firebaseUid, user.id);
  }

  return { mapping, created, reused };
}

async function importProfiles(data, userMapping) {
  const profileByUid = new Map(
    data.profiles.map((profile) => [profile.firebaseUid, profile]),
  );
  const rows = data.authUsers.map((user) => {
    const profile = profileByUid.get(user.firebaseUid);
    return {
      id: userMapping.get(user.firebaseUid),
      firebase_uid: user.firebaseUid,
      display_name: profile?.displayName || user.displayName || '',
      photo_path: null,
    };
  });
  await checked(
    supabase.from('profiles').upsert(rows, { onConflict: 'id' }),
    'supabase-import-profiles-failed',
  );
}

async function importGroups(data, userMapping) {
  const rows = data.groups.map((group) => ({
    firebase_id: group.firebaseId,
    owner_id: userMapping.get(group.createdBy),
    name: group.name,
    total_owed: 0,
    created_at: group.createdAt,
    updated_at: group.createdAt,
  }));
  await checked(
    supabase.from('groups').upsert(rows, { onConflict: 'firebase_id' }),
    'supabase-import-groups-failed',
  );
  const imported = await checked(
    supabase
      .from('groups')
      .select('id,firebase_id')
      .in(
        'firebase_id',
        data.groups.map((group) => group.firebaseId),
      ),
    'supabase-read-groups-failed',
  );
  return new Map(imported.map((group) => [group.firebase_id, group.id]));
}

async function importFriends(data, groupMapping) {
  const rows = [];
  for (const group of data.groups) {
    const groupId = groupMapping.get(group.firebaseId);
    for (const friendName of group.friends) {
      rows.push({
        firebase_id: stableFriendId(normalizedName(friendName)),
        group_id: groupId,
        name: friendName,
        created_at: group.createdAt,
        updated_at: group.createdAt,
      });
    }
  }
  for (const batch of chunked(rows)) {
    await checked(
      supabase
        .from('group_friends')
        .upsert(batch, { onConflict: 'group_id,firebase_id' }),
      'supabase-import-friends-failed',
    );
  }

  const friendMapping = new Map();
  for (const group of data.groups) {
    const groupId = groupMapping.get(group.firebaseId);
    const imported = await checked(
      supabase
        .from('group_friends')
        .select('id,name')
        .eq('group_id', groupId),
      'supabase-read-friends-failed',
    );
    for (const friend of imported) {
      friendMapping.set(
        `${groupId}:${normalizedName(friend.name)}`,
        friend.id,
      );
    }
  }
  return friendMapping;
}

function expenseTotals(expense) {
  return expense.shares.reduce(
    (totals, share) => ({
      base: roundCurrency(totals.base + share.baseAmount),
      tax: roundCurrency(totals.tax + share.taxAmount),
      service: roundCurrency(totals.service + share.serviceAmount),
      total: roundCurrency(totals.total + share.amount),
    }),
    { base: 0, tax: 0, service: 0, total: 0 },
  );
}

async function importExpenses(data, groupMapping) {
  const rows = [];
  for (const group of data.groups) {
    const groupId = groupMapping.get(group.firebaseId);
    for (const expense of group.expenses) {
      const totals = expenseTotals(expense);
      rows.push({
        firebase_id: expense.firebaseId,
        group_id: groupId,
        title: expense.title,
        base_total: totals.base,
        tax_percent: expense.taxPercent,
        service_percent: expense.servicePercent,
        tax_amount: totals.tax,
        service_amount: totals.service,
        total_with_charges: totals.total,
        expense_date: expense.expenseDate,
        created_at: expense.expenseDate,
        updated_at: expense.expenseDate,
      });
    }
  }
  for (const batch of chunked(rows)) {
    await checked(
      supabase
        .from('expenses')
        .upsert(batch, { onConflict: 'group_id,firebase_id' }),
      'supabase-import-expenses-failed',
    );
  }

  const expenseMapping = new Map();
  for (const group of data.groups) {
    const groupId = groupMapping.get(group.firebaseId);
    const imported = await checked(
      supabase
        .from('expenses')
        .select('id,firebase_id')
        .eq('group_id', groupId),
      'supabase-read-expenses-failed',
    );
    for (const expense of imported) {
      expenseMapping.set(
        `${group.firebaseId}:${expense.firebase_id}`,
        expense.id,
      );
    }
  }
  return expenseMapping;
}

async function importShares(
  data,
  groupMapping,
  friendMapping,
  expenseMapping,
) {
  const rows = [];
  const importedExpenseIds = [];

  for (const group of data.groups) {
    const groupId = groupMapping.get(group.firebaseId);
    for (const expense of group.expenses) {
      const expenseId = expenseMapping.get(
        `${group.firebaseId}:${expense.firebaseId}`,
      );
      if (!expenseId) fail('supabase-expense-mapping-missing');
      importedExpenseIds.push(expenseId);

      for (
        let sourceIndex = 0;
        sourceIndex < expense.shares.length;
        sourceIndex += 1
      ) {
        const share = expense.shares[sourceIndex];
        const friendId = friendMapping.get(
          `${groupId}:${normalizedName(share.friendName)}`,
        );
        if (!friendId) fail('supabase-friend-mapping-missing');
        rows.push({
          expense_id: expenseId,
          source_index: sourceIndex,
          friend_id: friendId,
          friend_name: share.friendName,
          description: share.description,
          base_amount: share.baseAmount,
          tax_amount: share.taxAmount,
          service_amount: share.serviceAmount,
          amount: share.amount,
          paid: share.paid,
          paid_at: share.paid ? share.paidAt : null,
          created_at: expense.expenseDate,
          updated_at: share.paidAt ?? expense.expenseDate,
        });
      }
    }
  }

  for (const batch of chunked(importedExpenseIds, 100)) {
    await checked(
      supabase.from('expense_shares').delete().in('expense_id', batch),
      'supabase-clear-shares-failed',
    );
  }
  for (const batch of chunked(rows)) {
    await checked(
      supabase.from('expense_shares').insert(batch),
      'supabase-import-shares-failed',
    );
  }
}

async function exactCount(table) {
  const result = await supabase
    .from(table)
    .select('*', { count: 'exact', head: true });
  if (result.error) {
    fail(`supabase-count-${table}-failed`, {
      causeCode: result.error.code,
      status: result.error.status,
    });
  }
  return result.count ?? 0;
}

async function verifyImport(data) {
  const expected = {
    profiles: data.authUsers.length,
    groups: data.groups.length,
    group_friends: data.groups.reduce(
      (total, group) => total + group.friends.length,
      0,
    ),
    expenses: data.groups.reduce(
      (total, group) => total + group.expenses.length,
      0,
    ),
    expense_shares: data.groups.reduce(
      (total, group) =>
        total +
        group.expenses.reduce(
          (expenseTotal, expense) =>
            expenseTotal + expense.shares.length,
          0,
        ),
      0,
    ),
  };
  const actual = {};
  for (const table of Object.keys(expected)) {
    actual[table] = await exactCount(table);
    if (actual[table] !== expected[table]) {
      fail('supabase-row-count-mismatch', { table });
    }
  }

  const [groups, expenses, shares, users] = await Promise.all([
    checked(
      supabase.from('groups').select('id,total_owed'),
      'supabase-verify-groups-failed',
    ),
    checked(
      supabase
        .from('expenses')
        .select(
          'id,group_id,base_total,tax_amount,service_amount,total_with_charges',
        ),
      'supabase-verify-expenses-failed',
    ),
    checked(
      supabase
        .from('expense_shares')
        .select(
          'expense_id,base_amount,tax_amount,service_amount,amount,paid',
        ),
      'supabase-verify-shares-failed',
    ),
    listSupabaseUsers(),
  ]);

  const sharesByExpense = new Map();
  for (const share of shares) {
    const values = sharesByExpense.get(share.expense_id) ?? [];
    values.push(share);
    sharesByExpense.set(share.expense_id, values);
  }
  for (const expense of expenses) {
    const expenseShares = sharesByExpense.get(expense.id) ?? [];
    const sums = expenseShares.reduce(
      (totals, share) => ({
        base: roundCurrency(totals.base + Number(share.base_amount)),
        tax: roundCurrency(totals.tax + Number(share.tax_amount)),
        service: roundCurrency(
          totals.service + Number(share.service_amount),
        ),
        total: roundCurrency(totals.total + Number(share.amount)),
      }),
      { base: 0, tax: 0, service: 0, total: 0 },
    );
    if (
      roundCurrency(expense.base_total) !== sums.base ||
      roundCurrency(expense.tax_amount) !== sums.tax ||
      roundCurrency(expense.service_amount) !== sums.service ||
      roundCurrency(expense.total_with_charges) !== sums.total
    ) {
      fail('supabase-expense-total-mismatch');
    }
  }

  const groupIdByExpenseId = new Map(
    expenses.map((expense) => [expense.id, expense.group_id]),
  );
  const unpaidByGroupId = new Map();
  for (const share of shares) {
    if (share.paid) continue;
    const groupId = groupIdByExpenseId.get(share.expense_id);
    if (!groupId) fail('supabase-share-group-mapping-missing');
    unpaidByGroupId.set(
      groupId,
      roundCurrency(
        (unpaidByGroupId.get(groupId) ?? 0) + Number(share.amount),
      ),
    );
  }
  for (const group of groups) {
    if (
      roundCurrency(group.total_owed) !==
      roundCurrency(unpaidByGroupId.get(group.id) ?? 0)
    ) {
      fail('supabase-group-total-mismatch');
    }
  }

  const expectedFirebaseUids = new Set(
    data.authUsers.map((user) => user.firebaseUid),
  );
  const importedUsers = users.filter((user) =>
    expectedFirebaseUids.has(cleanString(user.user_metadata?.firebase_uid)),
  );
  if (importedUsers.length !== data.authUsers.length) {
    fail('supabase-auth-user-count-mismatch');
  }
  const passwordReadyUsers = importedUsers.filter(
    (user) => user.app_metadata?.migration_password_ready === true,
  ).length;

  const paidShares = shares.filter((share) => share.paid).length;
  return {
    users: importedUsers.length,
    profiles: actual.profiles,
    groups: actual.groups,
    friends: actual.group_friends,
    expenses: actual.expenses,
    shares: actual.expense_shares,
    paidShares,
    groupTotalsVerified: groups.length,
    expenseTotalsVerified: expenses.length,
    passwordReadyUsers,
    usersRequiringPasswordReset: importedUsers.length - passwordReadyUsers,
  };
}

try {
  const serialized = await fs.readFile(exportPath, { encoding: 'utf8' });
  const expectedChecksum = cleanString(
    await fs.readFile(
      path.join(path.dirname(exportPath), 'firebase-export.sha256'),
      { encoding: 'utf8' },
    ),
  );
  if (checksum(serialized) !== expectedChecksum) {
    fail('firebase-export-checksum-mismatch');
  }

  const data = JSON.parse(serialized);
  if (data.version !== EXPORT_VERSION) fail('firebase-export-version-invalid');
  if (!Array.isArray(data.authUsers) || !Array.isArray(data.groups)) {
    fail('firebase-export-shape-invalid');
  }

  const authResult = await importAuthUsers(data);
  await importProfiles(data, authResult.mapping);
  const groupMapping = await importGroups(data, authResult.mapping);
  const friendMapping = await importFriends(data, groupMapping);
  const expenseMapping = await importExpenses(data, groupMapping);
  await importShares(
    data,
    groupMapping,
    friendMapping,
    expenseMapping,
  );
  const verification = await verifyImport(data);

  console.log(
    JSON.stringify(
      {
        authUsersCreated: authResult.created,
        authUsersReused: authResult.reused,
        ...verification,
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(
    JSON.stringify(
      sanitizeError(
        {
          ...error,
          code: error?.details?.causeCode ?? error?.code,
          status: error?.details?.status ?? error?.status,
        },
        'supabase-import',
      ),
    ),
  );
  process.exitCode = 1;
}
