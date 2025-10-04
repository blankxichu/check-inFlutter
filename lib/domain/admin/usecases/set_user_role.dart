import 'package:guardias_escolares/domain/admin/repositories/admin_repository.dart';

class SetUserRole {
  final AdminRepository repo;
  const SetUserRole(this.repo);
  Future<void> call({required String uid, required String role}) => repo.setUserRole(uid: uid, role: role);
}
