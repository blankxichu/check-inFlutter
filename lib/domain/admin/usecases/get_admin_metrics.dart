import 'package:guardias_escolares/domain/admin/entities/admin_metrics.dart';
import 'package:guardias_escolares/domain/admin/repositories/admin_repository.dart';

class GetAdminMetrics {
  final AdminRepository repo;
  const GetAdminMetrics(this.repo);
  Future<AdminMetrics> call(DateTime nowUtc) => repo.getMetrics(nowUtc: nowUtc);
}
