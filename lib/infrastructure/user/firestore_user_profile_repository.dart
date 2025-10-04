import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/domain/user/entities/user_profile.dart';
import 'package:guardias_escolares/domain/user/value_objects/user_stats.dart';
import 'package:guardias_escolares/domain/user/value_objects/user_preferences.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';
import 'package:guardias_escolares/domain/auth/entities/user_profile.dart' show UserRole; // enum

class FirestoreUserProfileRepository implements UserProfileRepository {
  final FirebaseFirestore _db;
  FirestoreUserProfileRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String,dynamic>> get _col => _db.collection('users');

  RichUserProfile? _fromDoc(DocumentSnapshot<Map<String,dynamic>> doc) {
    if (!doc.exists) return null;
    final data = doc.data()!;
    UserRole role;
    switch((data['role'] ?? 'parent').toString()) {
      case 'admin': role = UserRole.admin; break;
      default: role = UserRole.parent; break;
    }
    final statsData = (data['stats'] as Map<String,dynamic>?) ?? const {};
    final prefsData = (data['preferences'] as Map<String,dynamic>?) ?? const {};
    return RichUserProfile(
      uid: doc.id,
      email: (data['email'] ?? '') as String?,
      displayName: (data['displayName'] ?? data['name'] ?? '') as String?,
      avatarPath: (data['avatarPath'] ?? '') as String?,
      createdAt: ((data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc(),
      updatedAt: ((data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc(),
      role: role,
      stats: UserStats(
        totalSessions: (statsData['totalSessions'] as num?)?.toInt() ?? 0,
        openSessions: (statsData['openSessions'] as num?)?.toInt() ?? 0,
        totalWorkedMinutes: (statsData['totalWorkedMinutes'] as num?)?.toInt() ?? 0,
        lastCheckInAt: (statsData['lastCheckInAt'] as Timestamp?)?.toDate().toUtc(),
      ),
      preferences: UserPreferences(
        locale: prefsData['locale'] as String?,
        pushEnabled: (prefsData['pushEnabled'] as bool?) ?? true,
        darkMode: prefsData['darkMode'] as bool?,
      ),
    );
  }

  // _statsToMap eliminado: ahora se actualiza con paths planos para minimizar riesgos de invalid-argument

  Map<String,dynamic> _prefsToMap(UserPreferences p) => {
    if (p.locale != null) 'locale': p.locale,
    'pushEnabled': p.pushEnabled,
    if (p.darkMode != null) 'darkMode': p.darkMode,
  };

  @override
  Future<RichUserProfile?> fetchById(String uid) async {
    final doc = await _col.doc(uid).get();
    return _fromDoc(doc);
  }

  @override
  Stream<RichUserProfile?> watchById(String uid) => _col.doc(uid).snapshots().map(_fromDoc);

  @override
  Future<void> updateDisplayName(String uid, String displayName) async {
    await _col.doc(uid).set({
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateAvatarPath(String uid, String avatarPath, {DateTime? updatedAt}) async {
    await _col.doc(uid).set({
      'avatarPath': avatarPath,
      'avatarUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updatePreferences(String uid, UserPreferences prefs) async {
    await _col.doc(uid).set({
      'preferences': _prefsToMap(prefs),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateStats(String uid, UserStats stats) async {
    final docRef = _col.doc(uid);
    // STRATEGY CHANGE: Only use set() with merge, never update() to avoid any nested path issues
    final statsData = {
      'totalSessions': stats.totalSessions,
      'openSessions': stats.openSessions,
      'totalWorkedMinutes': stats.totalWorkedMinutes,
      if (stats.lastCheckInAt != null) 'lastCheckInAt': Timestamp.fromDate(stats.lastCheckInAt!.toUtc()),
    };
    
    try {
      // Always use set with merge - simplest and most reliable approach
      await docRef.set({
        'uid': uid,
        'stats': statsData,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // ignore: avoid_print
      print('updateStats SUCCESS for uid=$uid with stats=$statsData');
    } on FirebaseException catch (e) {
      // ignore: avoid_print  
      print('updateStats FAILED for uid=$uid, code=${e.code}, message=${e.message}, stats=$statsData');
      throw Exception('updateStats_failed(${e.code}): ${e.message} | statsData=$statsData');
    } catch (e) {
      // ignore: avoid_print
      print('updateStats UNKNOWN ERROR for uid=$uid: $e');
      rethrow;
    }
  }
}
