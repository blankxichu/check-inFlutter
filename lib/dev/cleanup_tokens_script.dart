// Script de desarrollo: Limpia campo 'uid' redundante de fcmTokens
//
// USO (solo para admins):
// 1. Importar en main.dart o ejecutar en debug:
//    import 'package:guardias_escolares/dev/cleanup_tokens_script.dart';
//
// 2. Llamar la función:
//    await runTokenCleanupMigration(dryRun: true); // Preview primero
//    await runTokenCleanupMigration(dryRun: false); // Ejecutar después
//
// 3. O desde Flutter DevTools console:
//    runTokenCleanupMigration(dryRun: true)
//
// REQUISITOS:
// - Usuario actual debe tener role: 'admin' en Firestore
// - Cloud Function 'cleanupTokensRedundantUid' desplegada

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Ejecuta la migración de limpieza de tokens
/// 
/// [dryRun]: Si es true, solo reporta qué haría sin modificar nada
/// [batchSize]: Número máximo de tokens a procesar por usuario (default: 500)
Future<void> runTokenCleanupMigration({
  bool dryRun = true,
  int batchSize = 500,
}) async {
  try {
    debugPrint('🔧 Iniciando migración de tokens...');
    debugPrint('   Modo: ${dryRun ? "DRY-RUN (solo lectura)" : "PRODUCCIÓN (escribirá cambios)"}');
    debugPrint('   Batch size: $batchSize');
    debugPrint('');

    final functions = FirebaseFunctions.instance;
    
    // Llamar a la Cloud Function
    final result = await functions.httpsCallable('cleanupTokensRedundantUid').call({
      'dryRun': dryRun,
      'batchSize': batchSize,
    });

    final data = result.data as Map<String, dynamic>;
    
    debugPrint('');
    debugPrint('=' * 60);
    debugPrint('📊 RESULTADO DE MIGRACIÓN');
    debugPrint('=' * 60);
    debugPrint('Tokens escaneados:       ${data['scanned']}');
    debugPrint('Tokens con campo uid:    ${data['cleaned']}');
    debugPrint('Tokens ya limpios:       ${data['skipped']}');
    debugPrint('Modo dry-run:            ${data['dryRun']}');
    debugPrint('Ahorro estimado:         ${(data['estimatedSavingsBytes'] / 1024).toStringAsFixed(2)} KB');
    debugPrint('=' * 60);
    debugPrint('');

    if (dryRun && data['cleaned'] > 0) {
      debugPrint('⚠️  DRY-RUN completado. Para aplicar cambios:');
      debugPrint('   await runTokenCleanupMigration(dryRun: false);');
      debugPrint('');
    } else if (!dryRun && data['cleaned'] > 0) {
      debugPrint('✅ Migración completada exitosamente');
      debugPrint('   ${data['cleaned']} tokens optimizados');
      debugPrint('');
    } else if (data['cleaned'] == 0) {
      debugPrint('✅ No se encontraron tokens con campo uid');
      debugPrint('   La base de datos ya está optimizada');
      debugPrint('');
    }

  } on FirebaseFunctionsException catch (e) {
    debugPrint('');
    debugPrint('❌ Error al ejecutar migración:');
    debugPrint('   Code: ${e.code}');
    debugPrint('   Message: ${e.message}');
    debugPrint('');
    
    if (e.code == 'permission-denied') {
      debugPrint('💡 SOLUCIÓN: Asegúrate de que tu usuario tenga role: "admin"');
      debugPrint('   Puedes verificar/asignar el rol usando la Cloud Function:');
      debugPrint('   await Functions.instance.httpsCallable("setUserRole").call({');
      debugPrint('     "targetUid": "TU_UID_AQUI",');
      debugPrint('     "role": "admin"');
      debugPrint('   });');
      debugPrint('');
    }
    
    rethrow;
  } catch (e) {
    debugPrint('');
    debugPrint('❌ Error inesperado: $e');
    debugPrint('');
    rethrow;
  }
}
