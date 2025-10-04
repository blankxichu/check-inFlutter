enum UserRole { parent, admin }

class UserProfile {
  final String uid;
  final String? email;
  final String? displayName;
  final UserRole role;

  const UserProfile({
    required this.uid,
    this.email,
    this.displayName,
    this.role = UserRole.parent,
  });
}
