#!/usr/bin/env node
/**
 * Enviar un push de prueba a un usuario (por uid) usando Admin SDK.
 * Uso:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   node tooling/send_test_notification.js checkin-flutter-cc702 <uid> "Titulo" "Cuerpo"
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

async function main() {
  const [projectId, uid, title, body] = process.argv.slice(2);
  if (!projectId || !uid) {
    console.error('Uso: node tooling/send_test_notification.js <projectId> <uid> "Titulo" "Cuerpo"');
    process.exit(1);
  }
  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();
  const messaging = getMessaging();

  const tSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
  const tokens = tSnap.docs.map((d) => d.id);
  if (tokens.length === 0) {
    console.log('No hay tokens para el usuario:', uid);
    return;
  }
  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: title || 'Prueba', body: body || 'Mensaje de prueba' },
    data: { body: body || '' },
  });
  console.log(`Enviados: ${res.successCount}, Fallidos: ${res.failureCount}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
