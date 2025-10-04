import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:guardias_escolares/domain/auth/entities/user_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/domain/auth/repositories/auth_repository.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class FirebaseAuthRepository implements AuthRepository {
  final fb.FirebaseAuth _auth;
  FirebaseAuthRepository({fb.FirebaseAuth? auth}) : _auth = auth ?? fb.FirebaseAuth.instance;

  UserProfile? _mapUser(fb.User? user) {
    if (user == null) return null;
    // Leer custom claims (si existen) desde IdTokenResult
    UserRole role = UserRole.parent;
    // Garantiza que este correo siempre sea admin
    final email = user.email?.toLowerCase();
    if (email == 'laraxichu@gmail.com') {
      role = UserRole.admin;
    }
    // Claims se obtienen en flows async (currentUser/signIn); aquí devolvemos parent por defecto.
  return UserProfile(uid: user.uid, email: user.email, displayName: user.displayName, role: role);
  }

  @override
  Stream<UserProfile?> authStateChanges() {
    return _auth.authStateChanges().map(_mapUser);
  }

  @override
  Future<UserProfile?> currentUser() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    UserRole role = UserRole.parent;
    final email = u.email?.toLowerCase();
    if (email == 'laraxichu@gmail.com') {
  final p = UserProfile(uid: u.uid, email: u.email, displayName: u.displayName, role: UserRole.admin);
      // Enriquecer Crashlytics
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier(p.uid);
        if (p.email != null) await FirebaseCrashlytics.instance.setCustomKey('user_email', p.email!);
        await FirebaseCrashlytics.instance.setCustomKey('user_role', 'admin');
      } catch (_) {}
      return p;
    }
    try {
      final token = await u.getIdTokenResult(true);
      final claims = token.claims ?? const {};
      final r = (claims['role'] as String?)?.toLowerCase();
      if (r == 'admin') role = UserRole.admin;
    } catch (_) {}
  final p = UserProfile(uid: u.uid, email: u.email, displayName: u.displayName, role: role);
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(p.uid);
      if (p.email != null) await FirebaseCrashlytics.instance.setCustomKey('user_email', p.email!);
      await FirebaseCrashlytics.instance.setCustomKey('user_role', role == UserRole.admin ? 'admin' : 'parent');
    } catch (_) {}
    return p;
  }

  @override
  Future<UserProfile> signInWithEmail({required String email, required String password}) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    final user = cred.user;
    if (user == null) {
      throw StateError('Authentication failed');
    }
    // Best-effort: sincronizar perfil a Firestore para vistas de admin
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email ?? email,
        if (user.displayName != null && user.displayName!.isNotEmpty) 'displayName': user.displayName,
        'role': 'parent', // no sobreescribe custom claims; solo referencia
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    UserRole role = UserRole.parent;
    final lowerEmail = (user.email ?? email).toLowerCase();
    if (lowerEmail == 'laraxichu@gmail.com') {
      role = UserRole.admin;
      final p = UserProfile(uid: user.uid, email: user.email, role: role);
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier(p.uid);
        if (p.email != null) await FirebaseCrashlytics.instance.setCustomKey('user_email', p.email!);
        await FirebaseCrashlytics.instance.setCustomKey('user_role', 'admin');
      } catch (_) {}
      return p;
    }
    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? const {};
      final r = (claims['role'] as String?)?.toLowerCase();
      if (r == 'admin') role = UserRole.admin;
    } catch (_) {}
  final p = UserProfile(uid: user.uid, email: user.email, displayName: user.displayName, role: role);
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(p.uid);
      if (p.email != null) await FirebaseCrashlytics.instance.setCustomKey('user_email', p.email!);
      await FirebaseCrashlytics.instance.setCustomKey('user_role', role == UserRole.admin ? 'admin' : 'parent');
    } catch (_) {}
    return p;
  }

  @override
  Future<UserProfile> signUpWithEmail({required String email, required String password, required String displayName}) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final user = cred.user;
    if (user == null) {
      throw StateError('Sign up failed');
    }
    // Actualizar displayName en Auth
    try {
      await user.updateDisplayName(displayName);
    } catch (_) {}
    // Guardar perfil en Firestore
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': email,
        'displayName': displayName,
        'role': 'parent',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  return UserProfile(uid: user.uid, email: user.email, displayName: displayName, role: UserRole.parent);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
