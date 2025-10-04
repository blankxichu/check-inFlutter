#!/usr/bin/env node
/**
 * Seed minimal Firestore documents used by the app.
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   node tooling/seed_firestore.js "checkin-flutter-cc702"
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

async function main() {
  const projectId = process.argv[2];
  if (!projectId) {
    console.error('Usage: node tooling/seed_firestore.js <projectId>');
    process.exit(1);
  }
  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();

  // Schools/default for geofence
  const schoolRef = db.collection('schools').doc('default');
  await schoolRef.set({
    lat: 21.224842738543487,
    lon: -99.92340204636226,
    radius: 100,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('Seeded schools/default');

  // Ping doc for connectivity
  const pingRef = db.collection('_ping').doc('x');
  await pingRef.set({ at: FieldValue.serverTimestamp() }, { merge: true });
  console.log('Seeded _ping/x');

  // Sample shift doc for today (UTC) with capacity 2 and no users
  const now = new Date();
  const utc = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const yyyy = utc.getUTCFullYear();
  const mm = String(utc.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(utc.getUTCDate()).padStart(2, '0');
  const dayId = `${yyyy}-${mm}-${dd}`;
  await db.collection('shifts').doc(dayId).set({
    date: utc,
    capacity: 2,
    users: [],
    seededAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log(`Seeded shifts/${dayId}`);
}

main().catch(err => { console.error(err); process.exit(1); });
