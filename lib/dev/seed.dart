import 'package:cloud_firestore/cloud_firestore.dart';

/// Siembra datos de ejemplo en la colección 'shifts'.
/// Crea 3 días a partir de hoy con capacidad 2 y sin usuarios asignados.
Future<void> seedShifts(FirebaseFirestore db) async {
  final now = DateTime.now().toUtc();
  final days = List.generate(3, (i) => DateTime.utc(now.year, now.month, now.day).add(Duration(days: i)));
  final batch = db.batch();
  for (final day in days) {
    final dayId = day.toIso8601String().substring(0, 10); // yyyy-MM-dd
    final ref = db.collection('shifts').doc(dayId);
    batch.set(ref, {
      'date': day, // Firestore convierte DateTime a Timestamp
      'users': <String>[],
      'capacity': 2,
    }, SetOptions(merge: true));
  }
  await batch.commit();
}
