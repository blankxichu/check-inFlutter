import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';

class FirebaseAvatarRepository implements AvatarRepository {
  final FirebaseStorage _storage;
  FirebaseAvatarRepository({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<String> uploadAvatarBytes({required String uid, required List<int> bytes, required String extension}) async {
    try {
      final ver = DateTime.now().millisecondsSinceEpoch.toString();
      final path = 'avatars/$uid/avatar_$ver.$extension';
      final ref = _storage.ref(path);
      
      final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final uploadTask = ref.putData(data, SettableMetadata(contentType: 'image/$extension'));
      
      await uploadTask;
      return ref.fullPath;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> deleteCurrentAvatar(String uid, {String? avatarPath}) async {
    if (avatarPath == null || avatarPath.isEmpty) return;
    try { await _storage.ref(avatarPath).delete(); } catch (_) {}
  }

  @override
  Future<Uri> getDownloadUri(String storagePath) async {
    final url = await _storage.ref(storagePath).getDownloadURL();
    return Uri.parse(url);
  }
}
