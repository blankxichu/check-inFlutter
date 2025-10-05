import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/application/chat/chat_providers.dart';
import 'package:guardias_escolares/presentation/screens/chat/chat_room_page.dart';

class UserPickerPage extends ConsumerStatefulWidget {
  const UserPickerPage({super.key});

  @override
  ConsumerState<UserPickerPage> createState() => _UserPickerPageState();
}

class _UserPickerPageState extends ConsumerState<UserPickerPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _users = <_PickerUser>[];
  bool _loading = false;
  bool _exhausted = false;
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  String _currentServerQuery = '';
  bool _serverSearching = false;
  final _serverResults = <_PickerUser>[];

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels + 300 >= _scrollCtrl.position.maxScrollExtent && !_loading && !_exhausted) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    setState(() => _loading = true);
    try {
      var q = FirebaseFirestore.instance.collection('users').orderBy('email');
      if (_lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }
      final snap = await q.limit(40).get();
      if (snap.docs.isEmpty) {
        _exhausted = true;
      } else {
        _lastDoc = snap.docs.last;
        for (final d in snap.docs) {
          final data = d.data();
          final email = (data['email'] ?? '') as String;
            // Algunos docs pueden no tener nombre; opcional
          final name = (data['displayName'] ?? data['name'] ?? '') as String?;
          final photoUrl = data['photoUrl'] as String?;
          final avatarPath = data['avatarPath'] as String?; // nuevo fallback
          final online = data['online'] == true;
          final lastActiveAt = data['lastActiveAt'] is Timestamp ? (data['lastActiveAt'] as Timestamp).toDate() : null;
          _users.add(_PickerUser(
            uid: d.id,
            email: email,
            displayName: name?.trim().isEmpty == true ? null : name,
            photoUrl: photoUrl,
            avatarPath: avatarPath,
            online: online,
            lastActiveAt: lastActiveAt,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando usuarios: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Búsqueda server-side por prefijo en campo normalizado (normalizedSearch) que combina email y displayName lowercased sin espacios.
  // Requiere crear y mantener ese campo (fuera de este cambio) en documentos de users.
  Future<void> _runServerSearch(String rawTerm) async {
    final term = rawTerm.trim().toLowerCase();
    _currentServerQuery = term;
    _serverResults.clear();
    if (term.length < 2) {
      setState(() {});
      return; // no buscar con 0-1 caracteres para ahorrar lecturas
    }
    setState(() => _serverSearching = true);
    try {
      final end = term.substring(0, term.length - 1) + String.fromCharCode(term.codeUnitAt(term.length - 1) + 1);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('normalizedSearch')
          .startAt([term])
          .endBefore([end])
          .limit(40)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final email = (data['email'] ?? '') as String;
        final name = (data['displayName'] ?? data['name'] ?? '') as String?;
        final photoUrl = data['photoUrl'] as String?;
        final avatarPath = data['avatarPath'] as String?; // nuevo fallback
        final online = data['online'] == true;
        final lastActiveAt = data['lastActiveAt'] is Timestamp ? (data['lastActiveAt'] as Timestamp).toDate() : null;
        _serverResults.add(_PickerUser(
          uid: d.id,
          email: email,
          displayName: name?.trim().isEmpty == true ? null : name,
          photoUrl: photoUrl,
          avatarPath: avatarPath,
          online: online,
          lastActiveAt: lastActiveAt,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error búsqueda: $e')));
      }
    } finally {
      if (mounted) setState(() => _serverSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(currentUserIdProvider);
    final term = _searchCtrl.text.trim().toLowerCase();
    if (_currentServerQuery != term) {
      // debounce ligero manual
      Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted && _searchCtrl.text.trim().toLowerCase() == term) {
          _runServerSearch(term);
        }
      });
    }
    final localFiltered = _users.where((u) {
      if (u.uid == myUid) return false;
      if (term.isEmpty) return true;
      return (u.email.toLowerCase().contains(term)) || (u.displayName?.toLowerCase().contains(term) == true);
    }).toList();
    final showing = term.length >= 2 ? _serverResults : localFiltered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar usuario'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar por email o nombre',
                suffixIcon: term.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _users.clear();
                _lastDoc = null;
                _exhausted = false;
                await _loadMore();
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: showing.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == showing.length) {
                    if (_exhausted) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: Text('Fin de la lista')),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Center(
                        child: term.length >= 2
                            ? (_serverSearching
                                ? const CircularProgressIndicator()
                                : Text('Resultados: ${showing.length}'))
                            : (_loading
                                ? const CircularProgressIndicator()
                                : TextButton(
                                    onPressed: _loadMore,
                                    child: const Text('Cargar más'),
                                  )),
                      ),
                    );
                  }
                  final u = showing[i];
                  return ListTile(
                    leading: _avatar(u),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(u.displayName ?? u.email,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        _presenceDot(u),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (u.displayName != null)
                          Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                        _lastActiveText(u),
                      ],
                    ),
                    onTap: () => _selectUser(u),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(_PickerUser u) {
    final base = u.displayName ?? u.email;
    final parts = base.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Future<void> _selectUser(_PickerUser user) async {
    final repo = ref.read(chatRepositoryProvider);
    try {
      final chatId = await repo.createOrGetDirectThread(user.uid);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatRoomPage(chatId: chatId)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creando chat: $e')));
      }
    }
  }

  Widget _avatar(_PickerUser u) {
    if (u.photoUrl != null && u.photoUrl!.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(u.photoUrl!), radius: 22);
    }
    if (u.avatarPath != null && u.avatarPath!.isNotEmpty) {
      final path = u.avatarPath!;
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.ref(path).getDownloadURL(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return CircleAvatar(radius: 22, child: Text(_initials(u)));
          }
            if (snap.hasData && snap.data != null) {
              return CircleAvatar(backgroundImage: NetworkImage(snap.data!), radius: 22);
            }
          return CircleAvatar(radius: 22, child: Text(_initials(u)));
        },
      );
    }
    return CircleAvatar(radius: 22, child: Text(_initials(u)));
  }

  Widget _presenceDot(_PickerUser u) {
    final color = u.online ? Colors.green : Colors.grey;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _lastActiveText(_PickerUser u) {
    if (u.online) return const Text('En línea', style: TextStyle(fontSize: 11, color: Colors.green));
    if (u.lastActiveAt == null) return const SizedBox.shrink();
    final diff = DateTime.now().difference(u.lastActiveAt!);
    String label;
    if (diff.inMinutes < 1) {
      label = 'Hace segundos';
    } else if (diff.inMinutes < 60) {
      label = 'Hace ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      label = 'Hace ${diff.inHours} h';
    } else {
      label = '${u.lastActiveAt!.day.toString().padLeft(2, '0')}/${u.lastActiveAt!.month.toString().padLeft(2, '0')}';
    }
    return Text('Últ. vez: $label', style: const TextStyle(fontSize: 11, color: Colors.black54));
  }
}

class _PickerUser {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? avatarPath; // ruta interna en storage
  final bool online;
  final DateTime? lastActiveAt;
  _PickerUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.avatarPath,
    this.online = false,
    this.lastActiveAt,
  });
}
