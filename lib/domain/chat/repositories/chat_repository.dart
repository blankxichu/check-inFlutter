import 'package:guardias_escolares/domain/chat/entities/chat_message.dart';
import 'package:guardias_escolares/domain/chat/entities/chat_thread.dart';

abstract class ChatRepository {
  Stream<List<ChatThread>> watchThreads();
  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit});
  Future<String> sendMessage({required String chatId, required String text});
  Future<String> createOrGetDirectThread(String otherUserId);
  Future<void> markThreadRead(String chatId);
  Future<void> markMessagesRead(String chatId, List<String> messageIds);
}
