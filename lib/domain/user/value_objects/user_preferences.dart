/// Preferencias configurables del usuario (presentación / notificaciones, etc.)
class UserPreferences {
  final String? locale; // ej: es-MX
  final bool pushEnabled;
  final bool? darkMode; // null => seguir sistema

  const UserPreferences({
    this.locale,
    this.pushEnabled = true,
    this.darkMode,
  });

  UserPreferences copyWith({
    String? locale,
    bool? pushEnabled,
    bool? darkMode,
  }) => UserPreferences(
        locale: locale ?? this.locale,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        darkMode: darkMode ?? this.darkMode,
      );
}
