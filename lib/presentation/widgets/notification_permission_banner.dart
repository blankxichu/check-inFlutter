import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class _NotifPermVisibility extends Notifier<bool> {
  @override
  bool build() {
    try {
      final box = Hive.box('app_cache');
      final denied = box.get('notif_perm_denied', defaultValue: false) as bool;
      final dismissed = box.get('notif_perm_dismissed', defaultValue: false) as bool;
      return denied && !dismissed;
    } catch (_) {
      return false;
    }
  }

  void hide({bool dismiss = true}) {
    if (dismiss) {
      try { Hive.box('app_cache').put('notif_perm_dismissed', true); } catch (_) {}
    }
    state = false;
  }

  void recheck() {
    state = build();
  }
}

final notificationPermissionBannerVisibilityProvider = NotifierProvider<_NotifPermVisibility, bool>(() => _NotifPermVisibility());

class NotificationPermissionBanner extends ConsumerWidget {
  const NotificationPermissionBanner({super.key});

  Future<void> _openSettings() async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      // Nota: En iOS para abrir ajustes del sistema se podría usar package app_settings si se añade.
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final visible = ref.watch(notificationPermissionBannerVisibilityProvider);
    if (!visible) return const SizedBox.shrink();
    return Material(
      color: Colors.amber.shade700,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.notifications_off, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Notificaciones desactivadas. Actívalas para recibir avisos de tus guardias.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await _openSettings();
                  // Re-evaluar permiso
                  final settings = await FirebaseMessaging.instance.getNotificationSettings();
                  if (settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional) {
                    try { Hive.box('app_cache').put('notif_perm_denied', false); } catch (_) {}
                    ref.read(notificationPermissionBannerVisibilityProvider.notifier).hide(dismiss: false);
                  }
                },
                child: const Text('Activar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: () {
                  ref.read(notificationPermissionBannerVisibilityProvider.notifier).hide(dismiss: true);
                },
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Cerrar',
              )
            ],
          ),
        ),
      ),
    );
  }
}
