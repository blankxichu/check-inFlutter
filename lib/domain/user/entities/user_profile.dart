import 'package:guardias_escolares/domain/auth/entities/user_profile.dart' show UserRole; // reutilizamos enum existente
import 'package:guardias_escolares/domain/user/value_objects/user_stats.dart';
import 'package:guardias_escolares/domain/user/value_objects/user_preferences.dart';

/// Perfil enriquecido del usuario (dominio). No depende de infraestructura.
class RichUserProfile {
  final String uid;
  final String? email;
  final String? displayName;
  final String? avatarPath; // ruta interna en Storage (no URL pública)
  final String? photoUrl; // URL directa (cacheada) cuando está disponible
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserRole role;
  final UserStats stats;
  final UserPreferences preferences;

  const RichUserProfile({
    required this.uid,
    this.email,
    this.displayName,
    this.avatarPath,
    this.photoUrl,
    required this.createdAt,
    required this.updatedAt,
    this.role = UserRole.parent,
    this.stats = const UserStats(),
    this.preferences = const UserPreferences(),
  });

  RichUserProfile copyWith({
    String? email,
    String? displayName,
    String? avatarPath,
  String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    UserRole? role,
    UserStats? stats,
    UserPreferences? preferences,
  }) => RichUserProfile(
        uid: uid,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        avatarPath: avatarPath ?? this.avatarPath,
    photoUrl: photoUrl ?? this.photoUrl,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        role: role ?? this.role,
        stats: stats ?? this.stats,
        preferences: preferences ?? this.preferences,
      );
}
