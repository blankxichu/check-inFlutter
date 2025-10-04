import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart' show AvatarRepository;

/// Use case: subir avatar, validar y actualizar perfil.
class UploadUserAvatar {
  final AvatarRepository avatars;
  final UserProfileRepository profiles;
  UploadUserAvatar({required this.avatars, required this.profiles});

  /// Sube la imagen y actualiza el path de avatar en el perfil.
  /// No hace compresión aquí (delegar a capa superior si se requiere).
  Future<void> call({required String uid, required List<int> bytes, required String extension}) async {
    // Validaciones mínimas (negocio ligero)
    if (bytes.isEmpty) {
      throw ArgumentError('Archivo vacío');
    }
    if (bytes.length > 2 * 1024 * 1024) { // >2MB
      throw StateError('El avatar supera el límite de 2MB');
    }
    final allowed = ['jpg','jpeg','png'];
    if (!allowed.contains(extension.toLowerCase())) {
      throw StateError('Formato no soportado ($extension)');
    }
    
    final path = await avatars.uploadAvatarBytes(uid: uid, bytes: bytes, extension: extension.toLowerCase());
    await profiles.updateAvatarPath(uid, path, updatedAt: DateTime.now().toUtc());
  }
}
