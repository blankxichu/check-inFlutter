import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/application/chat/chat_providers.dart';
import 'package:guardias_escolares/application/user/providers/user_profile_providers.dart';
import 'package:guardias_escolares/application/user/providers/avatar_cache_provider.dart';
import 'package:guardias_escolares/domain/user/entities/user_profile.dart';
import 'package:guardias_escolares/core/utils/date_formatter.dart';

class ChatRoomPage extends ConsumerStatefulWidget {
  final String chatId;
  const ChatRoomPage({super.key, required this.chatId});

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  int _messageLimit = 50;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    // Marcar leído después de un frame para no bloquear el build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRepositoryProvider).markThreadRead(widget.chatId);
      // Auto-scroll al último mensaje
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(
      chatMessagesProvider(
        ChatMessagesRequest(chatId: widget.chatId, limit: _messageLimit),
      ),
    );
    final myUid = ref.watch(currentUserIdProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
  backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        foregroundColor: theme.colorScheme.onSurface,
        title: _ChatTitle(chatId: widget.chatId, myUid: myUid),
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              data: (messages) {
                // Marcar mensajes como leídos (read receipts) para los que aún no tienen mi uid en readBy
                if (myUid != null) {
                  final unreadMsgIds = <String>[];
                  for (final m in messages) {
                    if (m.senderId != myUid && !m.readBy.containsKey(myUid)) {
                      unreadMsgIds.add(m.id);
                    }
                  }
                  if (unreadMsgIds.isNotEmpty) {
                    // fire and forget
                    ref.read(chatRepositoryProvider).markMessagesRead(widget.chatId, unreadMsgIds).catchError((_){});
                  }
                }
                if (_isLoadingMore) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _isLoadingMore = false);
                    }
                  });
                }

                final showLoadMoreButton = messages.length >= _messageLimit;
                final extraItems = (showLoadMoreButton || _isLoadingMore) ? 1 : 0;

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  itemCount: messages.length + extraItems,
                  itemBuilder: (_, i) {
                    if (extraItems == 1 && i == 0) {
                      if (_isLoadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _loadOlderMessages,
                            icon: const Icon(Icons.history),
                            label: const Text('Ver mensajes anteriores'),
                          ),
                        ),
                      );
                    }

                    final index = extraItems == 1 ? i - 1 : i;
                    final m = messages[index];
                    final isMe = myUid != null && m.senderId == myUid;
                    final allRead = m.readBy.length > 1; // simplista: si alguien más lo marcó
                    final timestamp = ChatDateFormatter.formatMessageTime(m.createdAt);
                    
                    // Verificar si necesitamos un separador de fecha
                    bool showDateSeparator = false;
                    String? separatorText;
                    
                    if (i == 0) {
                      // Primer mensaje: siempre mostrar separador
                      showDateSeparator = true;
                      separatorText = ChatDateFormatter.formatDateSeparator(m.createdAt);
                    } else {
                      // Comparar con el mensaje anterior
                      final prevMsg = messages[i - 1];
                      final prevDay = DateTime(prevMsg.createdAt.year, prevMsg.createdAt.month, prevMsg.createdAt.day);
                      final currentDay = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
                      
                      if (prevDay != currentDay) {
                        showDateSeparator = true;
                        separatorText = ChatDateFormatter.formatDateSeparator(m.createdAt);
                      }
                    }
                    
                    return Column(
                      children: [
                        // Separador de fecha si es necesario
                        if (showDateSeparator) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(child: Divider(color: Colors.grey.shade400)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    separatorText!,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: Colors.grey.shade400)),
                              ],
                            ),
                          ),
                        ],
                        // Mensaje
                        if (isMe)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    m.text,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          timestamp,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          allRead ? Icons.done_all : Icons.check,
                                          size: 14,
                                          color: allRead ? Colors.lightGreenAccent : Colors.white70,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          // Mensaje del otro: incluir avatar y timestamp
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SenderAvatar(uid: m.senderId),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        m.text,
                                        style: const TextStyle(color: Colors.black87),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        timestamp,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  // _isMine ya reemplazado directamente en build usando currentUserIdProvider.

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                hintText: 'Mensaje...',
                border: InputBorder.none,
              ),
              minLines: 1,
              maxLines: 5,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _send,
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await ref.read(chatRepositoryProvider).sendMessage(chatId: widget.chatId, text: text);
    // Auto scroll al final después de pequeño delay
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  void _loadOlderMessages() {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _messageLimit += 50;
    });
  }
}

/// Título dinámico del AppBar mostrando avatar y nombre del otro participante (en chats 1 a 1).
class _ChatTitle extends ConsumerWidget {
  final String chatId;
  final String? myUid;
  const _ChatTitle({required this.chatId, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatDocStream = FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
      stream: chatDocStream,
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Text('Chat');
        }
        final data = snap.data!.data()!;
        final parts = (data['participants'] as List?)?.cast<String>() ?? const <String>[];
        if (parts.length != 2) {
          return const Text('Chat');
        }
        final otherId = parts.firstWhere((p) => p != myUid, orElse: () => parts.first);
        final profileStream = ref.watch(getUserProfileProvider).watch(otherId);
        return StreamBuilder<RichUserProfile?>(
          stream: profileStream,
          builder: (context, profSnap) {
            final prof = profSnap.data;
            final display = prof?.displayName?.isNotEmpty == true ? prof!.displayName! : otherId;
            return Row(
              children: [
                _AvatarSmall(
                  avatarPath: prof?.avatarPath,
                  photoUrl: prof?.photoUrl,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AvatarSmall extends ConsumerWidget {
  final String? avatarPath;
  final String? photoUrl;
  const _AvatarSmall({this.avatarPath, this.photoUrl});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(photoUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    if (avatarPath == null || avatarPath!.isEmpty) {
      return const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16));
    }
    final avatarUrlAsync = ref.watch(avatarUrlProvider(avatarPath!));
    return avatarUrlAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16));
        }
        return CircleAvatar(
          radius: 16,
          backgroundImage: NetworkImage(url),
          onBackgroundImageError: (_, __) {},
        );
      },
      loading: () => const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
      error: (_, __) => const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
    );
  }
}

/// Avatar del remitente en cada mensaje entrante.
class _SenderAvatar extends ConsumerWidget {
  final String uid;
  const _SenderAvatar({required this.uid});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileStream = ref.watch(getUserProfileProvider).watch(uid);
    return StreamBuilder<RichUserProfile?>(
      stream: profileStream,
      builder: (context, snap) {
        final avatarPath = snap.data?.avatarPath;
        final photoUrl = snap.data?.photoUrl;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          return CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(photoUrl),
            onBackgroundImageError: (_, __) {},
          );
        }
        if (avatarPath == null || avatarPath.isEmpty) {
          return const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16));
        }
        // Usar provider cacheado
        final avatarUrlAsync = ref.watch(avatarUrlProvider(avatarPath));
        return avatarUrlAsync.when(
          data: (url) {
            if (url == null || url.isEmpty) {
              return const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16));
            }
            return CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(url),
              onBackgroundImageError: (_, __) {},
            );
          },
          loading: () => const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
          error: (_, __) => const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
        );
      },
    );
  }
}
