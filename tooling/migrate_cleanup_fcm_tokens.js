/**
 * Script de migración OPCIONAL: Elimina campo 'uid' redundante de fcmTokens
 * 
 * SEGURIDAD:
 * - Solo actualiza documentos existentes (no borra nada)
 * - Usa batch writes para atomicidad
 * - Puede ejecutarse múltiples veces (idempotente)
 * - Dry-run mode disponible para previsualización
 * 
 * USO:
 * 1. Dry-run (solo lectura):
 *    cd functions && node ../tooling/migrate_cleanup_fcm_tokens.js --dry-run
 * 
 * 2. Ejecución real:
 *    cd functions && node ../tooling/migrate_cleanup_fcm_tokens.js
 * 
 * NOTA: Debe ejecutarse desde el directorio functions/ para tener acceso
 * a firebase-admin y las credenciales de servicio.
 */

const admin = require('firebase-admin');
const path = require('path');

// Inicializar Firebase Admin con las credenciales del proyecto
if (!admin.apps.length) {
  try {
    // Intentar usar la service account key del directorio functions
    const serviceAccount = require(path.join(__dirname, '../functions/service-account-key.json'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin inicializado con service account key\n');
  } catch (e) {
    // Si no existe, intentar con credenciales por defecto
    try {
      admin.initializeApp();
      console.log('✅ Firebase Admin inicializado con credenciales por defecto\n');
    } catch (err) {
      console.error('❌ Error al inicializar Firebase Admin SDK');
      console.error('\nOpciones para configurar credenciales:');
      console.error('\n1. Descargar service account key:');
      console.error('   https://console.firebase.google.com/project/checkin-flutter-cc702/settings/serviceaccounts/adminsdk');
      console.error('   Guardar como: functions/service-account-key.json');
      console.error('\n2. O usar Firebase CLI (ejecutar desde functions/):');
      console.error('   cd functions && node ../tooling/migrate_cleanup_fcm_tokens.js --dry-run');
      console.error('\n3. O configurar variable de entorno:');
      console.error('   export GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccountKey.json\n');
      process.exit(1);
    }
  }
}

const db = admin.firestore();
const isDryRun = process.argv.includes('--dry-run');

async function cleanupUidField() {
  console.log('🔍 Buscando tokens con campo "uid" redundante...\n');
  
  if (isDryRun) {
    console.log('⚠️  MODO DRY-RUN: No se modificará nada\n');
  }

  const usersSnap = await db.collection('users').get();
  console.log(`📊 Usuarios encontrados: ${usersSnap.size}`);
  
  let totalTokens = 0;
  let tokensWithUid = 0;
  let updated = 0;
  let errors = 0;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const tokensSnap = await userDoc.ref.collection('fcmTokens').get();
    
    if (tokensSnap.empty) continue;
    
    totalTokens += tokensSnap.size;
    
    const batch = db.batch();
    let batchCount = 0;

    for (const tokenDoc of tokensSnap.docs) {
      const data = tokenDoc.data();
      
      // Solo actualizar si tiene el campo 'uid'
      if (data.uid !== undefined) {
        tokensWithUid++;
        
        if (!isDryRun) {
          batch.update(tokenDoc.ref, { 
            uid: admin.firestore.FieldValue.delete() 
          });
          batchCount++;
        }
      }
    }

    // Ejecutar batch si hay cambios
    if (!isDryRun && batchCount > 0) {
      try {
        await batch.commit();
        updated += batchCount;
        console.log(`✅ Usuario ${uid}: ${batchCount} tokens limpiados`);
      } catch (e) {
        errors++;
        console.error(`❌ Error en usuario ${uid}: ${e.message}`);
      }
    }
  }

  console.log('\n' + '='.repeat(60));
  console.log('📈 RESUMEN DE MIGRACIÓN');
  console.log('='.repeat(60));
  console.log(`Total de usuarios:           ${usersSnap.size}`);
  console.log(`Total de tokens:             ${totalTokens}`);
  console.log(`Tokens con campo 'uid':      ${tokensWithUid}`);
  
  if (isDryRun) {
    console.log(`\n⚠️  DRY-RUN: ${tokensWithUid} tokens SERÍAN limpiados`);
    console.log('Ejecuta sin --dry-run para aplicar cambios.\n');
  } else {
    console.log(`Tokens actualizados:         ${updated}`);
    console.log(`Errores:                     ${errors}`);
    
    if (updated > 0) {
      console.log(`\n✅ Migración completada exitosamente`);
      console.log(`Ahorro estimado: ~${(updated * 20 / 1024).toFixed(2)} KB`);
    } else if (tokensWithUid === 0) {
      console.log(`\n✅ No se encontraron tokens con campo 'uid'`);
      console.log('La migración ya fue aplicada o no es necesaria.');
    }
  }
  console.log('='.repeat(60) + '\n');
}

// Ejecutar con manejo de errores
cleanupUidField()
  .then(() => {
    console.log('✨ Script finalizado\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Error fatal durante la migración:');
    console.error(error);
    process.exit(1);
  });
