import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:guardias_escolares/domain/chat/entities/chat_message.dart';
import 'package:guardias_escolares/domain/chat/entities/chat_thread.dart';
import 'package:guardias_escolares/domain/chat/repositories/chat_repository.dart';

class FirestoreChatRepository implements ChatRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  FirestoreChatRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _threads => _db.collection('chats');

  @override
  Stream<List<ChatThread>> watchThreads() {
    return _threads
        .where('participants', arrayContains: _uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_mapThread).toList());
  }

  ChatThread _mapThread(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final last = data['lastMessage'] as Map<String, dynamic>?;
    DateTime? lastAt;
    if (last != null && last['createdAt'] is Timestamp) {
      lastAt = (last['createdAt'] as Timestamp).toDate();
    }
    final unread = <String, int>{};
    if (data['unread'] is Map<String, dynamic>) {
      (data['unread'] as Map<String, dynamic>).forEach((k, v) {
        unread[k] = (v is int) ? v : 0;
      });
    }
    return ChatThread(
      id: doc.id,
      participants: (data['participants'] is List) ? List<String>.from(data['participants']) : const <String>[],
      lastMessageText: last?['text'] as String?,
      lastMessageSenderId: last?['senderId'] as String?,
      lastMessageAt: lastAt,
      unread: unread,
    );
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = 100}) {
    return _threads
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => _mapMessage(chatId, d)).toList().reversed.toList());
  }

  ChatMessage _mapMessage(String chatId, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final readBy = <String, DateTime>{};
    if (data['readBy'] is Map<String, dynamic>) {
      (data['readBy'] as Map<String, dynamic>).forEach((k, v) {
        if (v is Timestamp) readBy[k] = v.toDate();
      });
    }
    return ChatMessage(
      id: doc.id,
      chatId: chatId,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] is Timestamp) ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
      readBy: readBy,
    );
  }

  @override
  Future<String> sendMessage({required String chatId, required String text}) async {
    final msgRef = _threads.doc(chatId).collection('messages').doc();
    await msgRef.set({
      'senderId': _uid,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'sent',
    });
    return msgRef.id;
  }

  @override
  Future<String> createOrGetDirectThread(String otherUserId) async {
    if (otherUserId == _uid) {
      throw StateError('No se puede crear chat consigo mismo');
    }
    final q = await _threads
        .where('participants', arrayContains: _uid)
        .limit(50)
        .get();
    for (final d in q.docs) {
      final parts = d.data()['participants'];
      if (parts is List && parts.contains(otherUserId) && parts.length == 2) {
        return d.id; // encontrado
      }
    }
    final newRef = _threads.doc();
    await newRef.set({
      'participants': [_uid, otherUserId],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'unread': {_uid: 0, otherUserId: 0},
    });
    return newRef.id;
  }

  @override
  Future<void> markThreadRead(String chatId) async {
    final ref = _threads.doc(chatId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final unread = Map<String, dynamic>.from(data['unread'] ?? {});
      if (unread[_uid] == 0) return;
      unread[_uid] = 0;
      tx.set(ref, {'unread': unread}, SetOptions(merge: true));
    });
  }

  @override
  Future<void> markMessagesRead(String chatId, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    for (final id in messageIds) {
      final ref = _threads.doc(chatId).collection('messages').doc(id);
      batch.set(ref, {
        'readBy': {
          _uid: now,
        }
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
