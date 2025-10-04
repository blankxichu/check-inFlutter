#!/usr/bin/env node
/**
 * Seed N check-ins for a user into Firestore.
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   node tooling/seed_checkins.js <projectId> <userIdOrDocId> [count]
 *
 * Notes:
 * - Uses Firebase Admin SDK (bypasses security rules).
 * - If you pass a value like "<uid>_<epochMs>", it will extract the UID before the first underscore.
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

function extractUid(input) {
  if (!input) return input;
  const idx = input.indexOf('_');
  return idx > 0 ? input.substring(0, idx) : input;
}

async function main() {
  const projectId = process.argv[2];
  const userInput = process.argv[3];
  const count = parseInt(process.argv[4] || '15', 10);

  if (!projectId || !userInput) {
    console.error('Usage: node tooling/seed_checkins.js <projectId> <userIdOrDocId> [count]');
    process.exit(1);
  }

  const userId = extractUid(userInput);
  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();

  // Base location (school) - near default used in seed script
  const baseLat = 21.224842738543487;
  const baseLon = -99.92340204636226;

  const now = Date.now();
  const batchSize = Math.max(1, count);
  let created = 0;

  for (let i = 0; i < batchSize; i++) {
    const tsMs = now - i * 60_000; // each one minute apart
    const ts = new Date(tsMs);
    const docId = `${userId}_${tsMs}`;
    // small jitter ~ +/- 0.0003 degrees (~30m)
    const jitterLat = (Math.random() - 0.5) * 0.0006;
    const jitterLon = (Math.random() - 0.5) * 0.0006;
    try {
      await db.collection('checkins').doc(docId).set({
        userId,
        timestamp: ts,
        lat: baseLat + jitterLat,
        lon: baseLon + jitterLon,
        seededAt: FieldValue.serverTimestamp(),
      }, { merge: false });
      created++;
      if (i % 5 === 4) {
        console.log(`Created ${created}/${batchSize} check-ins...`);
      }
    } catch (e) {
      console.error(`Failed to create ${docId}:`, e);
    }
  }

  console.log(`Done. Created ${created} check-ins for user ${userId}.`);
}

main().catch((err) => { console.error(err); process.exit(1); });
