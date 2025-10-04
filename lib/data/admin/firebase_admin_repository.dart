import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:guardias_escolares/domain/admin/entities/admin_metrics.dart';
import 'package:guardias_escolares/domain/admin/repositories/admin_repository.dart';

class FirebaseAdminRepository implements AdminRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  FirebaseAdminRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  Future<AdminMetrics> getMetrics({required DateTime nowUtc}) async {
    final startMonth = DateTime.utc(nowUtc.year, nowUtc.month, 1);
    final endMonth = DateTime.utc(nowUtc.year, nowUtc.month + 1, 0, 23, 59, 59, 999);
    final startDay = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final endDay = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 23, 59, 59, 999);

    // totalParents: contar documentos de users con rol parent (si tuvieras colección users top-level)
    int totalParents = 0;
    try {
      final users = await _db.collection('users').get();
      totalParents = users.docs.length;
    } catch (_) {}

    // totalShiftsThisMonth: contar turnos creados en rango (usando campo date)
    int totalShifts = 0;
    try {
      final qs = await _db
          .collection('shifts')
          .where('date', isGreaterThanOrEqualTo: startMonth)
          .where('date', isLessThanOrEqualTo: endMonth)
          .get();
      totalShifts = qs.docs.length;
    } catch (_) {}

    // totalCheckInsToday: contar checkins del día
    int totalCheckInsToday = 0;
    try {
      final qs = await _db
          .collection('checkins')
          .where('timestamp', isGreaterThanOrEqualTo: startDay)
          .where('timestamp', isLessThanOrEqualTo: endDay)
          .get();
      totalCheckInsToday = qs.docs.length;
    } catch (_) {}

    return AdminMetrics(
      totalParents: totalParents,
      totalShiftsThisMonth: totalShifts,
      totalCheckInsToday: totalCheckInsToday,
    );
  }

  @override
  Future<void> setUserRole({required String uid, required String role}) async {
    // Llama a una Cloud Function protegida que asigna custom claims
    await _functions.httpsCallable('setUserRole').call({'uid': uid, 'role': role});
  }
}
