import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Configuración de Firebase para la app (sin App Check en desarrollo)
class FirebaseConfig {
  /// Inicializa Firebase con configuración adecuada
  /// Retorna true si la inicialización fue exitosa
  static Future<bool> initialize({required bool enforceAppCheck}) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp();
      // Configuración de Firestore para desarrollo (persistencia y sin App Check)
      await _configureFirestoreForDev();
      return true;
    } catch (e) {
      debugPrint('Error en inicialización de Firebase: $e');
      return false;
    }
  }
  
  /// Configura Firestore para desarrollo (sin App Check)
  static Future<void> _configureFirestoreForDev() async {
    try {
      debugPrint('Inicializando Firebase sin App Check (modo desarrollo)');
      
      // Configuramos Firestore para uso en desarrollo
      FirebaseFirestore.instance.settings = 
          const Settings(persistenceEnabled: true);
          
    } catch (e) {
      debugPrint('Error configurando Firebase sin App Check: $e');
    }
  }
}