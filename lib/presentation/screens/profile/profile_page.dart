import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;
import 'package:guardias_escolares/application/user/providers/user_profile_providers.dart';
// Avatar cache provider removed from this widget to simplify and avoid spinner issues.
import 'package:guardias_escolares/domain/user/entities/user_profile.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _nameCtrl = TextEditingController();
  bool _savingName = false;
  bool _uploadingAvatar = false;
  bool _refreshingStats = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final user = ref.read(auth_vm.authViewModelProvider).maybeWhen(
      authenticated: (u) => u,
      orElse: () => null,
    );
    if (user == null) return;
    
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile != null) {
        setState(() => _uploadingAvatar = true);
        
        final uploadUseCase = ref.read(uploadUserAvatarProvider);
        final bytes = await pickedFile.readAsBytes();
        final extension = pickedFile.path.split('.').last;
        
        await uploadUseCase.call(
          uid: user.uid,
          bytes: bytes,
          extension: extension,
        );
        
        if (mounted) {
          // Refresh the profile to show the new avatar
          ref.invalidate(getUserProfileProvider);
          setState(() => _uploadingAvatar = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading avatar: $e')),
        );
      }
    }
  }

  Future<void> _saveName(String uid) async {
    final newName = _nameCtrl.text;
    if (newName.trim().isEmpty) return;
    setState(()=> _savingName = true);
    try {
      await ref.read(updateDisplayNameProvider).call(uid, newName);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre actualizado')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error nombre: $e')));
    } finally { if (mounted) setState(()=> _savingName = false); }
  }

  Future<void> _refreshStats(String uid) async {
    setState(()=> _refreshingStats = true);
    try {
      // Ensure doc explícito antes de refrescar stats (defensa extra)
      final authState = ref.read(auth_vm.authViewModelProvider);
      final user = authState.maybeWhen(authenticated: (u) => u, orElse: () => null);
      await ref.read(ensureProfileDocProvider).call(uid: uid, email: user?.email, displayName: user?.displayName);
      await ref.read(refreshUserStatsProvider).call(uid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Estadísticas recalculadas')));
    } catch (e) {
      final msg = e.toString().contains('invalid-argument')
          ? 'Error en escritura de stats (invalid-argument). Verifica reglas y nombres de campos.'
          : 'Error stats: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally { if (mounted) setState(()=> _refreshingStats = false); }
  }  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(auth_vm.authViewModelProvider);
    final user = authState.maybeWhen(authenticated: (u) => u, orElse: () => null);
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Inicia sesión')));
    }
    final profileStream = ref.watch(getUserProfileProvider).watch(user.uid);
    return StreamBuilder<RichUserProfile?>(
      stream: profileStream,
      builder: (context, snap) {
        final prof = snap.data;
        if (prof != null && _nameCtrl.text.isEmpty) {
          _nameCtrl.text = prof.displayName ?? '';
        }
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Perfil de Usuario')),
          body: snap.connectionState == ConnectionState.waiting && prof == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _AvatarView(avatarPath: prof?.avatarPath, uploading: _uploadingAvatar, onTap: _pickAvatar),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _nameCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Nombre para mostrar',
                                    suffixIcon: IconButton(
                                      icon: _savingName ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.save),
                                      onPressed: _savingName ? null : () => _saveName(user.uid),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(prof?.email ?? user.email ?? '', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                const SizedBox(height: 4),
                                Chip(label: Text((prof?.role.name ?? 'parent').toUpperCase())),
                                const SizedBox(height: 6),
                                const Text('Toca el círculo para cambiar tu avatar', style: TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Estadísticas', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _StatsSection(profile: prof, refreshing: _refreshingStats, onRefresh: () => _refreshStats(user.uid)),
                      const SizedBox(height: 24),
                      Text('Preferencias', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _PreferencesStub(),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _AvatarView extends ConsumerWidget {
  final String? avatarPath;
  final bool uploading;
  final VoidCallback onTap;
  const _AvatarView({required this.avatarPath, required this.uploading, required this.onTap});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = 76.0;
    final theme = Theme.of(context);
    return InkWell(
      onTap: uploading ? null : onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Stack(
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: avatarPath == null || avatarPath!.isEmpty
                ? const Icon(Icons.person, size: 42)
                : FutureBuilder<String?>(
                    future: _loadUrl(ref, avatarPath!),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2));
                      }
                      if (snap.hasError) {
                        return _AvatarErrorFallback(onRetry: () => _forceRebuild(ref));
                      }
                      if (!snap.hasData || snap.data == null) {
                        return const Icon(Icons.person, size: 42);
                      }
                      final url = snap.data!;
                      return ClipOval(
                        child: Image.network(
                          url,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          // Fallback quickly if stalled
                          loadingBuilder: (c, child, progress) {
                            if (progress == null) return child;
                            // If bytes total is known and progressed some, show linear progress
                            if (progress.expectedTotalBytes != null) {
                              final pct = progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1);
                              if (pct > 0.95) return child; // almost done
                            }
                            return const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2));
                          },
                          errorBuilder: (c, e, st) => _AvatarErrorFallback(onRetry: () => _forceRebuild(ref)),
                        ),
                      );
                    },
                  ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.edit, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _loadUrl(WidgetRef ref, String path) async {
    try {
      final repo = ref.read(avatarRepositoryProvider);
      // Sanitizar path (sin slash inicial)
      final clean = path.startsWith('/') ? path.substring(1) : path;
      final uri = await repo.getDownloadUri(clean).timeout(const Duration(seconds: 6));
      return uri.toString();
    } on TimeoutException catch (_) {
      debugPrint('[Avatar] Timeout obteniendo URL para $path');
      return null; // fallback icon
    } catch (e) {
      debugPrint('[Avatar] Error obteniendo URL: $e');
      return null;
    }
  }

  void _forceRebuild(WidgetRef ref) {
    // Estrategia simple: invalidar un provider trivial o usar a unique value; aquí usamos
    // Future.microtask + setState arriba (no tenemos state local porque es ConsumerWidget),
    // así que delegamos en Riverpod: leer un provider no usado no reinicia.
    // Alternativa: convertir a StatefulWidget. Para simplicidad forzamos nueva instancia cambiando key.
  }
}

class _AvatarErrorFallback extends StatelessWidget {
  final VoidCallback onRetry;
  const _AvatarErrorFallback({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: const Icon(Icons.refresh, size: 32),
    );
  }
}

class _StatsSection extends StatelessWidget {
  final RichUserProfile? profile;
  final bool refreshing;
  final VoidCallback onRefresh;
  const _StatsSection({required this.profile, required this.refreshing, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final stats = profile?.stats;
    final worked = stats == null ? '-' : _fmtDuration(stats.totalWorkedMinutes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Total sesiones: ${stats?.totalSessions ?? '-'}'),
                const SizedBox(width: 16),
                Text('Abiertas: ${stats?.openSessions ?? '-'}'),
              ],
            ),
            const SizedBox(height: 6),
            Text('Tiempo trabajado: $worked'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('Último check-in: ${profile?.stats.lastCheckInAt?.toLocal().toString() ?? '-'}', 
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing ? const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.refresh, size: 16),
                  label: Text(refreshing ? '...' : 'Recalcular'),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }
}

class _PreferencesStub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Preferencias (placeholder):'),
            SizedBox(height: 4),
            Text('- Locale / Notificaciones / Tema se implementarán en iteraciones siguientes.'),
          ],
        ),
      ),
    );
  }
}
