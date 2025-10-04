import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart';
import 'package:guardias_escolares/presentation/screens/calendar/calendar_page.dart';
import 'package:guardias_escolares/presentation/screens/checkin/check_in_page.dart';
// import 'package:guardias_escolares/presentation/screens/attendance/attendance_page.dart';
// import 'package:cloud_functions/cloud_functions.dart';
import 'package:guardias_escolares/presentation/screens/admin/admin_dashboard_page.dart';
import 'package:guardias_escolares/presentation/screens/profile/profile_page.dart';
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
  final cs = Theme.of(context).colorScheme;

    final isAdmin = state is AuthAuthenticated && state.user.role == UserRole.admin;
    final pages = <Widget>[
      const CalendarPage(), // 0
      const CheckInPage(),  // 1
      if (isAdmin) const AdminDashboardPage(), // 2 (si admin)
      const ProfilePage(), // último (2 si no admin, 3 si admin)
    ];

    final bodyContent = pages[_index];
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
                currentAccountPicture: CircleAvatar(
                  backgroundColor: cs.primary,
                  child: const Icon(Icons.person_outline, color: Colors.white),
                ),
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
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Admin'),
                  selected: _index == 2,
                  onTap: () => setState(() => _index = 2),
                ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                selected: _index == (isAdmin ? 3 : 2),
                onTap: () => setState(() => _index = isAdmin ? 3 : 2),
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
                    child: Text('Notifs: rec=${m.received} mostradas=${m.displayed}'),
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
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendario'),
          const NavigationDestination(icon: Icon(Icons.fingerprint_outlined), selectedIcon: Icon(Icons.fingerprint), label: 'Check-in'),
          if (isAdmin)
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings), label: 'Admin'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

// Old home body removed after adding Drawer and NavigationBar for better UX.
