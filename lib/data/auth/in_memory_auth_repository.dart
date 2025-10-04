import 'dart:async';

import 'package:guardias_escolares/domain/auth/entities/user_profile.dart';
import 'package:guardias_escolares/domain/auth/repositories/auth_repository.dart';

class InMemoryAuthRepository implements AuthRepository {
  final _controller = StreamController<UserProfile?>.broadcast();
  UserProfile? _current;

  @override
  Stream<UserProfile?> authStateChanges() => _controller.stream;

  @override
  Future<UserProfile?> currentUser() async => _current;

  @override
  Future<UserProfile> signInWithEmail({required String email, required String password}) async {
    // Simple in-memory user; in real use, validate inputs properly.
    _current = UserProfile(uid: 'local-${email.hashCode}', email: email);
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<UserProfile> signUpWithEmail({required String email, required String password, required String displayName}) async {
    _current = UserProfile(uid: 'local-${email.hashCode}', email: email);
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }
}
