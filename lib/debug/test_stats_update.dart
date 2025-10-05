import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Test directo para debuggear updateStats sin capas adicionales
class TestStatsUpdate {
  static Future<void> runDirectTest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('ERROR: No hay usuario autenticado');
        return;
      }
      
      final uid = user.uid;
      debugPrint('Testing updateStats para uid: $uid');
      
      // Test 1: Leer documento actual
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await docRef.get();
      debugPrint('Documento existe: ${snap.exists}');
      if (snap.exists) {
        debugPrint('Datos actuales: ${snap.data()}');
      }
      
      // Test 2: Intentar escritura mínima
      final testStats = {
        'totalSessions': 1,
        'openSessions': 0,
        'totalWorkedMinutes': 30,
        'lastCheckInAt': Timestamp.now(),
      };
      
  debugPrint('Intentando escribir stats: $testStats');
      
      await docRef.set({
        'uid': uid,
        'stats': testStats,
        'updatedAt': FieldValue.serverTimestamp(),
        'testFlag': 'debug_${DateTime.now().millisecondsSinceEpoch}',
      }, SetOptions(merge: true));
      
  debugPrint('SUCCESS: Escritura completada sin errores');
      
      // Test 3: Verificar escritura
      final newSnap = await docRef.get();
      debugPrint('Datos después de escribir: ${newSnap.data()}');
      
    } catch (e, stack) {
      debugPrint('ERROR en test directo: $e');
      debugPrint('Stack: $stack');
      
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
        debugPrint('Firebase error plugin: ${e.plugin}');
      }
    }
  }
  
  static Future<void> testUserPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user authenticated');
        return;
      }
      
      debugPrint('User UID: ${user.uid}');
      debugPrint('User email: ${user.email}');
      debugPrint('User token result:');
      
      final token = await user.getIdTokenResult();
      debugPrint('Claims: ${token.claims}');
      debugPrint('Auth time: ${token.authTime}');
      debugPrint('Issued at: ${token.issuedAtTime}');
      
    } catch (e) {
      debugPrint('Error getting user info: $e');
    }
  }
}