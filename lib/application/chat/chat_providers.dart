import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/data/chat/firestore_chat_repository.dart';
import 'package:guardias_escolares/domain/chat/entities/chat_message.dart';
import 'package:guardias_escolares/domain/chat/entities/chat_thread.dart';
import 'package:guardias_escolares/domain/chat/repositories/chat_repository.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return FirestoreChatRepository();
});

final chatThreadsProvider = StreamProvider<List<ChatThread>>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchThreads();
});

@immutable
class ChatMessagesRequest {
  const ChatMessagesRequest({required this.chatId, required this.limit});

  final String chatId;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is ChatMessagesRequest && other.chatId == chatId && other.limit == limit;

  @override
  int get hashCode => Object.hash(chatId, limit);
}

final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, ChatMessagesRequest>((ref, request) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchMessages(request.chatId, limit: request.limit);
});

// UID actual (o null si no autenticado) para UI de chat
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authViewModelProvider);
  return authState.maybeWhen(authenticated: (u) => u.uid, orElse: () => null);
});
