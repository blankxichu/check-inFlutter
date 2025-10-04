import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:guardias_escolares/domain/user/value_objects/user_stats.dart';

/// Test directo para debuggear updateStats sin capas adicionales
class TestStatsUpdate {
  static Future<void> runDirectTest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ERROR: No hay usuario autenticado');
        return;
      }
      
      final uid = user.uid;
      print('Testing updateStats para uid: $uid');
      
      // Test 1: Leer documento actual
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await docRef.get();
      print('Documento existe: ${snap.exists}');
      if (snap.exists) {
        print('Datos actuales: ${snap.data()}');
      }
      
      // Test 2: Intentar escritura mínima
      final testStats = {
        'totalSessions': 1,
        'openSessions': 0,
        'totalWorkedMinutes': 30,
        'lastCheckInAt': Timestamp.now(),
      };
      
      print('Intentando escribir stats: $testStats');
      
      await docRef.set({
        'uid': uid,
        'stats': testStats,
        'updatedAt': FieldValue.serverTimestamp(),
        'testFlag': 'debug_${DateTime.now().millisecondsSinceEpoch}',
      }, SetOptions(merge: true));
      
      print('SUCCESS: Escritura completada sin errores');
      
      // Test 3: Verificar escritura
      final newSnap = await docRef.get();
      print('Datos después de escribir: ${newSnap.data()}');
      
    } catch (e, stack) {
      print('ERROR en test directo: $e');
      print('Stack: $stack');
      
      if (e is FirebaseException) {
        print('Firebase error code: ${e.code}');
        print('Firebase error message: ${e.message}');
        print('Firebase error plugin: ${e.plugin}');
      }
    }
  }
  
  static Future<void> testUserPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user authenticated');
        return;
      }
      
      print('User UID: ${user.uid}');
      print('User email: ${user.email}');
      print('User token result:');
      
      final token = await user.getIdTokenResult();
      print('Claims: ${token.claims}');
      print('Auth time: ${token.authTime}');
      print('Issued at: ${token.issuedAtTime}');
      
    } catch (e) {
      print('Error getting user info: $e');
    }
  }
}