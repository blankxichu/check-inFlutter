import 'package:guardias_escolares/domain/user/entities/user_profile.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';

class GetUserProfile {
  final UserProfileRepository repo;
  GetUserProfile(this.repo);

  Future<RichUserProfile?> call(String uid) => repo.fetchById(uid);
  Stream<RichUserProfile?> watch(String uid) => repo.watchById(uid);
}
