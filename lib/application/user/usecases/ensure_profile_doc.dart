import 'package:cloud_firestore/cloud_firestore.dart';

/// Asegura un documento base en /users/{uid} con estructura mínima segura.
class EnsureProfileDoc {
  final FirebaseFirestore db;
  EnsureProfileDoc({FirebaseFirestore? firestore}) : db = firestore ?? FirebaseFirestore.instance;

  Future<void> call({required String uid, String? email, String? displayName}) async {
    final ref = db.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        if (email != null) 'email': email,
        if (displayName != null) 'displayName': displayName,
        'role': 'parent',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // Normaliza tipos corruptos de stats si fueran string / lista
  final data = snap.data();
      final stats = data?['stats'];
      if (stats != null && stats is! Map) {
        await ref.update({'stats': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()});
      }
    }
  }
}
