import 'package:guardias_escolares/domain/user/entities/user_profile.dart';
import 'package:guardias_escolares/domain/user/value_objects/user_stats.dart';
import 'package:guardias_escolares/domain/user/value_objects/user_preferences.dart';

/// Contrato para acceder y modificar perfiles de usuario.
abstract class UserProfileRepository {
  Future<RichUserProfile?> fetchById(String uid);
  Stream<RichUserProfile?> watchById(String uid);
  Future<void> updateDisplayName(String uid, String displayName);
  Future<void> updateAvatarPath(String uid, String avatarPath, {DateTime? updatedAt});
  Future<void> updatePreferences(String uid, UserPreferences prefs);
  Future<void> updateStats(String uid, UserStats stats);
}

/// Contrato para operaciones de avatar en Storage.
abstract class AvatarRepository {
  Future<String> uploadAvatarBytes({required String uid, required List<int> bytes, required String extension});
  Future<void> deleteCurrentAvatar(String uid, {String? avatarPath});
  Future<Uri> getDownloadUri(String storagePath);
}
