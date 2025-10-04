import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/data/auth/firebase_auth_repository.dart';
import 'package:guardias_escolares/data/auth/in_memory_auth_repository.dart';
import 'package:guardias_escolares/domain/auth/entities/user_profile.dart';
import 'package:guardias_escolares/domain/auth/repositories/auth_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  // Prefer Firebase if initialized; otherwise, fall back to local in-memory repo
  try {
    if (Firebase.apps.isNotEmpty) {
      return FirebaseAuthRepository();
    }
  } catch (_) {
    // ignore and fallback
  }
  return InMemoryAuthRepository();
});

sealed class AuthState {
  const AuthState();
  T when<T>({
    required T Function() unknown,
    required T Function() unauthenticated,
    required T Function(UserProfile user) authenticated,
    required T Function(String message) error,
    required T Function() loading,
  }) {
    final self = this;
    if (self is AuthUnknown) return unknown();
    if (self is AuthUnauthenticated) return unauthenticated();
    if (self is AuthAuthenticated) return authenticated(self.user);
    if (self is AuthError) return error(self.message);
    if (self is AuthLoading) return loading();
    throw StateError('Unhandled state: $self');
  }

  T maybeWhen<T>({
    T Function()? unknown,
    T Function()? unauthenticated,
    T Function(UserProfile user)? authenticated,
    T Function(String message)? error,
    T Function()? loading,
    required T Function() orElse,
  }) {
    final self = this;
    if (self is AuthUnknown && unknown != null) return unknown();
    if (self is AuthUnauthenticated && unauthenticated != null) return unauthenticated();
    if (self is AuthAuthenticated && authenticated != null) return authenticated(self.user);
    if (self is AuthError && error != null) return error(self.message);
    if (self is AuthLoading && loading != null) return loading();
    return orElse();
  }
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  final UserProfile user;
  const AuthAuthenticated(this.user);
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthViewModel extends Notifier<AuthState> {
  late final AuthRepository _repo;

  @override
  AuthState build() {
    _repo = ref.read(authRepositoryProvider);
    // Keep state in sync with Firebase
    ref.onDispose(_repo.authStateChanges().listen((user) {
      if (user == null) {
        state = const AuthUnauthenticated();
      } else {
        state = AuthAuthenticated(user);
      }
    }).cancel);
    return const AuthUnknown();
  }

  Future<void> signIn(String email, String password) async {
    state = const AuthLoading();
    try {
      final user = await _repo.signInWithEmail(email: email, password: password);
      state = AuthAuthenticated(user);
    } catch (e) {
      state = AuthError(e.toString());
      state = const AuthUnauthenticated();
    }
  }

  Future<void> signUp(String email, String password, String displayName) async {
    state = const AuthLoading();
    try {
      final user = await _repo.signUpWithEmail(email: email, password: password, displayName: displayName);
      state = AuthAuthenticated(user);
    } catch (e) {
      state = AuthError(e.toString());
      state = const AuthUnauthenticated();
    }
  }

  Future<void> signOut() async {
    // Intentar limpiar token FCM local asociado al usuario saliente para evitar contaminación cross-usuario
    try {
      if (Firebase.apps.isNotEmpty) {
        // Necesitamos el uid actual antes de cerrar sesión
        final current = state;
        String? uid;
        if (current is AuthAuthenticated) uid = current.user.uid;
        if (uid != null) {
          // Obtiene token y elimina doc
          // Import dinámico local para evitar dependencia arriba
          // ignore: import_of_legacy_library_into_null_safe
          final messaging = await Future.sync(() => FirebaseMessaging.instance);
          final token = await messaging.getToken();
          if (token != null) {
            final fs = FirebaseFirestore.instance;
            await fs.collection('users').doc(uid).collection('fcmTokens').doc(token).delete().catchError((_){});
          }
        }
      }
    } catch (_) {}
    await _repo.signOut();
  }
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(() {
  return AuthViewModel();
});
