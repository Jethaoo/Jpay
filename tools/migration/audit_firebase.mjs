import fs from 'node:fs';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

const credentialPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
const storageBucket = process.env.FIREBASE_STORAGE_BUCKET;

if (!credentialPath) {
  throw new Error('FIREBASE_SERVICE_ACCOUNT_PATH is required.');
}
if (!storageBucket) {
  throw new Error('FIREBASE_STORAGE_BUCKET is required.');
}

const serviceAccount = JSON.parse(
  fs.readFileSync(credentialPath, { encoding: 'utf8' }),
);

initializeApp({
  credential: cert(serviceAccount),
  storageBucket,
});

const auth = getAuth();
const firestore = getFirestore();
const bucket = getStorage().bucket();

async function auditUsers() {
  let pageToken;
  let userCount = 0;
  let passwordUserCount = 0;
  let verifiedUserCount = 0;
  const providers = {};

  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      userCount += 1;
      if (user.emailVerified) verifiedUserCount += 1;

      const providerIds = user.providerData.map(
        (provider) => provider.providerId,
      );
      if (providerIds.includes('password')) passwordUserCount += 1;
      for (const providerId of providerIds) {
        providers[providerId] = (providers[providerId] ?? 0) + 1;
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);

  return {
    users: userCount,
    passwordUsers: passwordUserCount,
    verifiedUsers: verifiedUserCount,
    providers,
  };
}

async function auditFirestore() {
  const [profilesSnapshot, groupsSnapshot] = await Promise.all([
    firestore.collection('users').get(),
    firestore.collection('groups').get(),
  ]);

  let expenses = 0;
  let modernExpenses = 0;
  let legacyExpenses = 0;
  let shares = 0;
  let paidShares = 0;
  let groupsWithDuplicateFriends = 0;

  for (const groupDocument of groupsSnapshot.docs) {
    const group = groupDocument.data();
    const friends = Array.isArray(group.friends)
      ? group.friends
          .map((friend) => String(friend).trim().toLowerCase())
          .filter(Boolean)
      : [];
    if (new Set(friends).size !== friends.length) {
      groupsWithDuplicateFriends += 1;
    }

    const expenseSnapshot = await groupDocument.ref
      .collection('expenses')
      .get();
    expenses += expenseSnapshot.size;

    for (const expenseDocument of expenseSnapshot.docs) {
      const expense = expenseDocument.data();
      if (Array.isArray(expense.debts)) {
        modernExpenses += 1;
        shares += expense.debts.length;
        paidShares += expense.debts.filter(
          (share) => share?.paid === true,
        ).length;
      } else {
        legacyExpenses += 1;
        shares += 1;
        if (expense.paid === true) paidShares += 1;
      }
    }
  }

  return {
    profiles: profilesSnapshot.size,
    groups: groupsSnapshot.size,
    expenses,
    modernExpenses,
    legacyExpenses,
    shares,
    paidShares,
    groupsWithDuplicateFriends,
  };
}

async function auditStorage() {
  try {
    let pageToken;
    let files = 0;
    let profilePictures = 0;

    do {
      const [batch, , response] = await bucket.getFiles({
        autoPaginate: false,
        maxResults: 1000,
        pageToken,
      });
      files += batch.filter((file) => !file.name.endsWith('/')).length;
      profilePictures += batch.filter(
        (file) =>
          !file.name.endsWith('/') &&
          file.name.startsWith('user_profile_pics/'),
      ).length;
      pageToken = response?.nextPageToken;
    } while (pageToken);

    return { available: true, files, profilePictures };
  } catch (error) {
    return {
      available: false,
      files: 0,
      profilePictures: 0,
      errorCode: String(error?.code ?? 'unknown'),
    };
  }
}

try {
  const [authSummary, firestoreSummary, storageSummary] = await Promise.all([
    auditUsers(),
    auditFirestore(),
    auditStorage(),
  ]);

  console.log(
    JSON.stringify(
      {
        projectId: serviceAccount.project_id,
        storageBucket,
        auth: authSummary,
        firestore: firestoreSummary,
        storage: storageSummary,
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(
    JSON.stringify({
      error: error?.name ?? 'MigrationAuditError',
      code: String(error?.code ?? 'unknown'),
    }),
  );
  process.exitCode = 1;
}
