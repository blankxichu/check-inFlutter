import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// App Check comentado temporalmente - está interfiriendo con FCM y notificaciones
// import 'package:firebase_app_check/firebase_app_check.dart';

/// Configuración de Firebase para la app (sin App Check en desarrollo)
class FirebaseConfig {
  /// Inicializa Firebase con configuración adecuada
  /// Retorna true si la inicialización fue exitosa
  static Future<bool> initialize({required bool enforceAppCheck}) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp();
      
      // App Check DESHABILITADO - interfiere con notificaciones push
      // await _configureAppCheckDebug();
      
      // Configuración de Firestore para desarrollo (persistencia y sin App Check)
      await _configureFirestoreForDev();
      return true;
    } catch (e) {
      debugPrint('Error en inicialización de Firebase: $e');
      return false;
    }
  }
  
  /* App Check comentado temporalmente - interfiere con notificaciones
  /// Configura App Check en modo debug para eliminar warnings
  static Future<void> _configureAppCheckDebug() async {
    try {
      debugPrint('Configurando App Check en modo debug...');
      
      await FirebaseAppCheck.instance.activate(
        // Usar debug provider en desarrollo para evitar warnings
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      );
      
      debugPrint('App Check activado en modo debug (sin enforcement)');
    } catch (e) {
      debugPrint('Error configurando App Check: $e');
    }
  }
  */
  
  /// Configura Firestore para desarrollo (sin App Check)
  static Future<void> _configureFirestoreForDev() async {
    try {
      debugPrint('Inicializando Firebase (modo desarrollo - sin App Check)');
      
      // Configuramos Firestore para uso en desarrollo
      FirebaseFirestore.instance.settings = 
          const Settings(persistenceEnabled: true);
          
    } catch (e) {
      debugPrint('Error configurando Firestore: $e');
    }
  }
}