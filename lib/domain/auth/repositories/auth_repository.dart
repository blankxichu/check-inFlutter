import 'package:guardias_escolares/domain/auth/entities/user_profile.dart';

abstract class AuthRepository {
  Stream<UserProfile?> authStateChanges();
  Future<UserProfile?> currentUser();
  Future<UserProfile> signInWithEmail({required String email, required String password});
  Future<UserProfile> signUpWithEmail({required String email, required String password, required String displayName});
  Future<void> signOut();
}
