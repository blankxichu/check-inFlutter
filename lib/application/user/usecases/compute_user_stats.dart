import 'package:guardias_escolares/domain/user/value_objects/user_stats.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';

/// Caso de uso placeholder: en el futuro calculará stats a partir de eventos.
class ComputeAndStoreUserStats {
  final UserProfileRepository profiles;
  ComputeAndStoreUserStats(this.profiles);

  Future<void> call({required String uid, required UserStats stats}) async {
    await profiles.updateStats(uid, stats);
  }
}
