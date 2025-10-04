import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';

class UpdateUserDisplayName {
  final UserProfileRepository repo;
  UpdateUserDisplayName(this.repo);

  Future<void> call(String uid, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw StateError('Nombre vacío');
    if (trimmed.length > 60) throw StateError('Nombre demasiado largo');
    await repo.updateDisplayName(uid, trimmed);
  }
}
