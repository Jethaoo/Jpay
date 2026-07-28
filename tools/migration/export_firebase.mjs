import fs from 'node:fs/promises';
import path from 'node:path';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import {
  EXPORT_VERSION,
  checksum,
  cleanString,
  fail,
  finiteNumber,
  normalizedName,
  roundCurrency,
  sanitizeError,
  timestampToIso,
} from './migration_common.mjs';

const credentialPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
const outputDirectory = path.resolve(
  process.env.MIGRATION_OUTPUT_DIRECTORY ?? 'output',
);

if (!credentialPath) {
  fail('firebase-service-account-path-required');
}

const serviceAccount = JSON.parse(
  await fs.readFile(credentialPath, { encoding: 'utf8' }),
);

initializeApp({ credential: cert(serviceAccount) });

const auth = getAuth();
const firestore = getFirestore();
const exportedAt = new Date().toISOString();

function positiveAmount(value, code) {
  const amount = roundCurrency(value);
  if (amount <= 0) fail(code);
  return amount;
}

function optionalPercent(value) {
  const percent = finiteNumber(value);
  return percent >= 0 ? percent : 0;
}

function transformShare(rawShare, expense, expenseDate) {
  const friendName = cleanString(rawShare?.friendName);
  if (!friendName) fail('expense-share-friend-required');

  const hasBaseAmount =
    rawShare?.baseAmount != null &&
    cleanString(String(rawShare.baseAmount)) !== '' &&
    Number.isFinite(Number(rawShare.baseAmount));
  const baseAmount = positiveAmount(
    hasBaseAmount ? rawShare.baseAmount : rawShare?.amount,
    'expense-share-base-amount-invalid',
  );

  let taxAmount = 0;
  let serviceAmount = 0;
  if (hasBaseAmount) {
    taxAmount = roundCurrency(rawShare?.taxAmount);
    serviceAmount = roundCurrency(rawShare?.serviceAmount);
  } else {
    const expenseBaseTotal = finiteNumber(expense?.totalAmount);
    if (expenseBaseTotal > 0) {
      const ratio = baseAmount / expenseBaseTotal;
      taxAmount = roundCurrency(finiteNumber(expense?.taxAmount) * ratio);
      serviceAmount = roundCurrency(
        finiteNumber(expense?.serviceAmount) * ratio,
      );
    }
  }

  const paid = rawShare?.paid === true;
  return {
    friendName,
    description: cleanString(rawShare?.description),
    baseAmount,
    taxAmount: Math.max(0, taxAmount),
    serviceAmount: Math.max(0, serviceAmount),
    amount: roundCurrency(baseAmount + taxAmount + serviceAmount),
    paid,
    paidAt: paid
      ? timestampToIso(rawShare?.paidAt, expenseDate)
      : null,
  };
}

function transformExpense(documentId, expense, groupCreatedAt) {
  const expenseDate = timestampToIso(
    expense?.date,
    timestampToIso(expense?.createdAt, groupCreatedAt ?? exportedAt),
  );
  const title = cleanString(expense?.title);
  if (!title) fail('expense-title-required');

  const rawShares = Array.isArray(expense?.debts)
    ? expense.debts
    : [
        {
          friendName: expense?.owedBy,
          description: '',
          amount: expense?.amount,
          paid: expense?.paid,
          paidAt: expense?.paidAt,
        },
      ];
  if (rawShares.length === 0) fail('expense-shares-required');

  const shares = rawShares.map((share) =>
    transformShare(share, expense, expenseDate),
  );
  return {
    firebaseId: documentId,
    title,
    expenseDate,
    taxPercent: optionalPercent(expense?.taxPercent),
    servicePercent: optionalPercent(expense?.servicePercent),
    shares,
  };
}

async function exportAuthUsers() {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      const email = cleanString(user.email).toLocaleLowerCase('en-US');
      if (!email) fail('auth-user-email-required');
      users.push({
        firebaseUid: user.uid,
        email,
        emailVerified: user.emailVerified === true,
        disabled: user.disabled === true,
        displayName: cleanString(user.displayName),
        createdAt: timestampToIso(user.metadata?.creationTime, exportedAt),
      });
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

async function exportProfiles() {
  const snapshot = await firestore.collection('users').get();
  return snapshot.docs.map((document) => {
    const profile = document.data();
    return {
      firebaseUid: document.id,
      displayName: cleanString(profile?.displayName),
      photoUrl: cleanString(profile?.photoUrl) || null,
    };
  });
}

async function exportGroups() {
  const snapshot = await firestore.collection('groups').get();
  const groups = [];

  for (const document of snapshot.docs) {
    const group = document.data();
    const name = cleanString(group?.name);
    const createdBy = cleanString(group?.createdBy);
    if (!name) fail('group-name-required');
    if (!createdBy) fail('group-owner-required');

    const createdAt = timestampToIso(group?.createdAt, exportedAt);
    const expenseSnapshot = await document.ref.collection('expenses').get();
    const expenses = expenseSnapshot.docs.map((expenseDocument) =>
      transformExpense(expenseDocument.id, expenseDocument.data(), createdAt),
    );

    const friendsByNormalizedName = new Map();
    for (const friend of Array.isArray(group?.friends) ? group.friends : []) {
      const friendName = cleanString(friend);
      if (friendName) {
        friendsByNormalizedName.set(normalizedName(friendName), friendName);
      }
    }
    for (const expense of expenses) {
      for (const share of expense.shares) {
        friendsByNormalizedName.set(
          normalizedName(share.friendName),
          share.friendName,
        );
      }
    }

    groups.push({
      firebaseId: document.id,
      createdBy,
      name,
      createdAt,
      friends: [...friendsByNormalizedName.values()],
      expenses,
    });
  }
  return groups;
}

function validateExport(data) {
  const uidSet = new Set(data.authUsers.map((user) => user.firebaseUid));
  if (uidSet.size !== data.authUsers.length) fail('duplicate-auth-uid');

  const emailSet = new Set(data.authUsers.map((user) => user.email));
  if (emailSet.size !== data.authUsers.length) fail('duplicate-auth-email');

  for (const profile of data.profiles) {
    if (!uidSet.has(profile.firebaseUid)) fail('profile-owner-not-in-auth');
  }

  const groupIds = new Set();
  const groupNamesByOwner = new Set();
  for (const group of data.groups) {
    if (!uidSet.has(group.createdBy)) fail('group-owner-not-in-auth');
    if (groupIds.has(group.firebaseId)) fail('duplicate-group-id');
    groupIds.add(group.firebaseId);

    const ownerNameKey = `${group.createdBy}:${normalizedName(group.name)}`;
    if (groupNamesByOwner.has(ownerNameKey)) {
      fail('duplicate-group-name-for-owner');
    }
    groupNamesByOwner.add(ownerNameKey);

    const expenseIds = new Set();
    const friendNames = new Set(
      group.friends.map((friend) => normalizedName(friend)),
    );
    if (friendNames.size !== group.friends.length) {
      fail('duplicate-group-friend');
    }

    for (const expense of group.expenses) {
      if (expenseIds.has(expense.firebaseId)) fail('duplicate-expense-id');
      expenseIds.add(expense.firebaseId);
      for (const share of expense.shares) {
        if (!friendNames.has(normalizedName(share.friendName))) {
          fail('share-friend-not-in-group');
        }
      }
    }
  }
}

function buildSummary(data) {
  const expenses = data.groups.flatMap((group) => group.expenses);
  const shares = expenses.flatMap((expense) => expense.shares);
  return {
    version: data.version,
    users: data.authUsers.length,
    profiles: data.profiles.length,
    groups: data.groups.length,
    friends: data.groups.reduce(
      (total, group) => total + group.friends.length,
      0,
    ),
    expenses: expenses.length,
    shares: shares.length,
    paidShares: shares.filter((share) => share.paid).length,
    disabledUsers: data.authUsers.filter((user) => user.disabled).length,
    usersRequiringPasswordReset: data.authUsers.length,
  };
}

try {
  const [authUsers, profiles, groups] = await Promise.all([
    exportAuthUsers(),
    exportProfiles(),
    exportGroups(),
  ]);
  const data = {
    version: EXPORT_VERSION,
    exportedAt,
    sourceProject: cleanString(serviceAccount.project_id),
    authUsers,
    profiles,
    groups,
  };
  validateExport(data);

  const serialized = `${JSON.stringify(data, null, 2)}\n`;
  const summary = buildSummary(data);
  await fs.mkdir(outputDirectory, { recursive: true });
  await fs.writeFile(
    path.join(outputDirectory, 'firebase-export.json'),
    serialized,
    { encoding: 'utf8', flag: 'wx' },
  );
  await fs.writeFile(
    path.join(outputDirectory, 'firebase-export.sha256'),
    `${checksum(serialized)}\n`,
    { encoding: 'utf8', flag: 'wx' },
  );
  await fs.writeFile(
    path.join(outputDirectory, 'firebase-export-summary.json'),
    `${JSON.stringify(summary, null, 2)}\n`,
    { encoding: 'utf8', flag: 'wx' },
  );
  console.log(JSON.stringify(summary, null, 2));
} catch (error) {
  console.error(JSON.stringify(sanitizeError(error, 'firebase-export')));
  process.exitCode = 1;
}
