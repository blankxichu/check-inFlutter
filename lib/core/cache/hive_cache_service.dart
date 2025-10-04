import 'package:hive_flutter/hive_flutter.dart';

/// Servicio simple de cache local con Hive para claves/valores y etiquetas de usuarios
class HiveCacheService {
  static const _appBoxName = 'app_cache';

  Box<dynamic> get _box => Hive.box<dynamic>(_appBoxName);

  String _userLabelKey(String uid) => 'user_label_$uid';

  Future<void> saveUserLabel(String uid, String label) async {
    await _box.put(_userLabelKey(uid), label);
  }

  String? getUserLabel(String uid) {
    final v = _box.get(_userLabelKey(uid));
    return v is String ? v : null;
  }

  Future<void> putString(String key, String value) async => _box.put(key, value);
  String? getString(String key) => _box.get(key) as String?;

  Future<void> putJson(String key, Map<String, dynamic> value) async => _box.put(key, value);
  Map<String, dynamic>? getJson(String key) {
    final v = _box.get(key);
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}
