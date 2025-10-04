import 'package:guardias_escolares/domain/admin/entities/admin_metrics.dart';

abstract class AdminRepository {
  Future<AdminMetrics> getMetrics({required DateTime nowUtc});
  Future<void> setUserRole({required String uid, required String role}); // 'admin' | 'parent'
}
