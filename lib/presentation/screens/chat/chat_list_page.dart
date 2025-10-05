import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/application/chat/chat_providers.dart';
import 'package:guardias_escolares/domain/chat/entities/chat_thread.dart';
import 'chat_room_page.dart';
import 'user_picker_page.dart';

class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(chatThreadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: threadsAsync.when(
        data: (threads) => _buildList(context, threads),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.chat),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UserPickerPage()),
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext ctx, List<ChatThread> threads) {
    if (threads.isEmpty) {
      return const Center(child: Text('No hay chats aún'));
    }
    return ListView.builder(
      itemCount: threads.length,
      itemBuilder: (_, i) {
        final t = threads[i];
        final subtitle = t.lastMessageText ?? 'Sin mensajes';
        final unreadTotal = t.unread.values.fold<int>(0, (p, c) => p + (c));
        return ListTile(
          title: Text(t.participants.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: unreadTotal > 0 ? CircleAvatar(radius: 12, child: Text(unreadTotal.toString())) : null,
          onTap: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ChatRoomPage(chatId: t.id))),
        );
      },
    );
  }
}
