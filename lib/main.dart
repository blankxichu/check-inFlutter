import 'package:flutter/material.dart';
import 'dart:ui' as ui show PlatformDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/core/app.dart';
// (Navigation handled now in GuardiasApp via notificationEventsProvider listener)
import 'package:guardias_escolares/core/firebase/firebase_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/dev/seed.dart' as devseed;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // Inicializa Hive para cache local
    await Hive.initFlutter();
    // Abre cajas comunes; las específicas se abrirán bajo demanda
    await Hive.openBox('app_cache');

    // Inicializar Firebase con configuración para desarrollo (App Check desactivado)
    // NOTA: Cambiar a true cuando la API de App Check esté habilitada completamente
    final firebaseInitialized = await FirebaseConfig.initialize(enforceAppCheck: false);
    
    if (!firebaseInitialized) {
      debugPrint('Error crítico: No se pudo inicializar Firebase');
    }
    // Seeder opcional: pasar --dart-define=SEED_SHIFTS=true para sembrar
    const seedFlag = String.fromEnvironment('SEED_SHIFTS');
    if (seedFlag.toLowerCase() == 'true') {
      await devseed.seedShifts(FirebaseFirestore.instance);
      debugPrint('Seeding de shifts completado');
    }
    // Habilitar Crashlytics si Firebase está activo
    if (firebaseInitialized) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      ui.PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      // Asegurar que la colección esté habilitada (útil en debug)
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      // Enviar inmediatamente reportes pendientes al iniciar
      await FirebaseCrashlytics.instance.sendUnsentReports();
    }
  } catch (e, st) {
    // Allow app to run without Firebase during early phases or tests
    debugPrint('Error en inicialización: $e');
    // Intenta registrar en Crashlytics si ya está disponible
    try { FirebaseCrashlytics.instance.recordError(e, st); } catch (_) {}
  }
  
  // App Check está desactivado en desarrollo por diseño para evitar interrupciones.
  
  runApp(const ProviderScope(child: GuardiasApp()));

  // Después del runApp, configuramos escucha de notificaciones para deep linking simple.
  // (Sincrónico differido para asegurar que ProviderScope está listo)
  // Deep link configurado ahora dentro de GuardiasApp; se eliminó hack posterior a runApp.
}
