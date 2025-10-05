import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart';
import 'package:guardias_escolares/application/user/providers/user_profile_providers.dart';
import 'package:guardias_escolares/application/user/providers/avatar_cache_provider.dart';
import 'package:guardias_escolares/presentation/screens/calendar/calendar_page.dart';
import 'package:guardias_escolares/presentation/screens/checkin/check_in_page.dart';
// import 'package:guardias_escolares/presentation/screens/attendance/attendance_page.dart';
// import 'package:cloud_functions/cloud_functions.dart';
import 'package:guardias_escolares/presentation/screens/admin/admin_dashboard_page.dart';
import 'package:guardias_escolares/presentation/screens/profile/profile_page.dart';
// Eliminado ChatListPage: navegación directa al selector de usuarios de chat
import 'package:guardias_escolares/presentation/screens/chat/user_picker_page.dart';
import 'package:guardias_escolares/domain/auth/entities/user_profile.dart';
import 'package:guardias_escolares/presentation/widgets/notification_permission_banner.dart';
import 'package:guardias_escolares/core/notifications/notification_metrics.dart';
import 'package:guardias_escolares/core/notifications/push_messaging_service.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;

  String _firstName(String fullNameOrEmail) {
    final s = fullNameOrEmail.trim();
    if (s.isEmpty) return 'Usuario';
    // If it's an email, take part before '@'
    final namePart = s.contains('@') ? s.split('@').first : s;
    final parts = namePart.split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    final candidate = parts.isNotEmpty ? parts.first : namePart;
    // Cap length to avoid layout issues
    return candidate.length > 18 ? '${candidate.substring(0, 18)}…' : candidate;
  }

  @override
  void dispose() {
    // Limpia el foco al abandonar la pantalla
    try { FocusManager.instance.primaryFocus?.unfocus(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authViewModelProvider);
  final userEmail = state is AuthAuthenticated ? state.user.email ?? state.user.uid : '-';
  final displayName = state is AuthAuthenticated ? (state.user.displayName ?? state.user.email ?? state.user.uid) : 'Invitado';
  // colorScheme local eliminado (no necesario directamente)

    final isAdmin = state is AuthAuthenticated && state.user.role == UserRole.admin;
    final pages = <Widget>[
      const CalendarPage(), // 0
      const CheckInPage(),  // 1
      const UserPickerPage(), // 2
      if (isAdmin) const AdminDashboardPage(), // 3 si admin
      const ProfilePage(), // último (3 si no admin, 4 si admin)
    ];

    final maxIndex = pages.length - 1;
    final safeIndex = _index.clamp(0, maxIndex);
    if (safeIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _index = safeIndex);
        }
      });
    }

    final bodyContent = pages[safeIndex];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardias Escolares'),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserAccountsDrawerHeader(
                currentAccountPicture: _MiniAvatar(userState: state),
                accountName: Text(
                  'Hola, ${_firstName(displayName)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                accountEmail: Text(
                  state is AuthAuthenticated && state.user.role == UserRole.admin ? 'Administrador' : userEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Calendario'),
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Check-in'),
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Mensajes'),
                selected: _index == 2,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _index = 2);
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Admin'),
                  selected: _index == 3,
                  onTap: () => setState(() => _index = 3),
                ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                selected: _index == (isAdmin ? 4 : 3),
                onTap: () => setState(() => _index = isAdmin ? 4 : 3),
              ),
              if (!bool.fromEnvironment('dart.vm.product')) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Desarrollo', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Consumer(builder: (context, ref, _) {
                  final m = ref.watch(notificationMetricsProvider);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text('Notifs rec:${m.received} mostr:${m.displayed}'),
                  );
                }),
                Row(
                  children: [
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () {
                        ref.read(notificationMetricsProvider.notifier).reset();
                      },
                      child: const Text('Reset métricas'),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(pushMessagingProvider).replayInitialEvent();
                      },
                      child: const Text('Replay inicial'),
                    ),
                  ],
                ),
                if (state is AuthAuthenticated)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Ver info usuario (debug)'),
                    onTap: () async {
                      final user = state.user;
                      if (!mounted) return;
                      await showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Información del Usuario'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('UID: ${user.uid}') ,
                              const SizedBox(height: 8),
                              Text('Email: ${user.email ?? 'Sin email'}'),
                              const SizedBox(height: 8),
                              Text('Role: ${user.role}') ,
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
                          ],
                        ),
                      );
                      if (!mounted) return;
                    },
                  ),
              ],
              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión'),
                onTap: () => ref.read(authViewModelProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          const NotificationPermissionBanner(),
          Expanded(child: bodyContent),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendario'),
          const NavigationDestination(icon: Icon(Icons.fingerprint_outlined), selectedIcon: Icon(Icons.fingerprint), label: 'Check-in'),
          const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Mensajes'),
          if (isAdmin)
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings), label: 'Admin'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _MiniAvatar extends ConsumerWidget {
  final AuthState userState;
  const _MiniAvatar({required this.userState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userState is! AuthAuthenticated) {
      return const CircleAvatar(child: Icon(Icons.person_outline));
    }
    final authUser = (userState as AuthAuthenticated).user;
    final profileStream = ref.watch(getUserProfileProvider).watch(authUser.uid);
    return StreamBuilder(
      stream: profileStream,
      builder: (context, snap) {
        final prof = snap.data;
        final avatarPath = prof?.avatarPath;
        if (avatarPath == null || avatarPath.isEmpty) {
          return CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(_initialsFrom(authUser.displayName ?? authUser.email ?? authUser.uid)),
          );
        }
        return FutureBuilder<String?>(
          future: ref.read(avatarUrlProvider(avatarPath).future),
          builder: (context, urlSnap) {
            if (urlSnap.hasData && urlSnap.data != null) {
              return CircleAvatar(backgroundImage: NetworkImage(urlSnap.data!),);
            }
            return CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(_initialsFrom(authUser.displayName ?? authUser.email ?? authUser.uid)),
            );
          },
        );
      },
    );
  }

  String _initialsFrom(String base) {
    final parts = base.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0,1).toUpperCase();
    return (parts[0].substring(0,1) + parts[1].substring(0,1)).toUpperCase();
  }
}

// ChatListPage eliminado: se abre directamente UserPickerPage desde el Drawer.
