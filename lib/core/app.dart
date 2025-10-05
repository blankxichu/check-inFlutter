import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/screens/auth/login_page.dart';
import 'package:guardias_escolares/presentation/screens/home/home_page.dart';
import 'package:guardias_escolares/presentation/screens/calendar/calendar_page.dart';
import 'package:guardias_escolares/presentation/screens/chat/chat_room_page.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart';
import 'package:guardias_escolares/core/notifications/push_messaging_service.dart';
import 'package:guardias_escolares/domain/notifications/notification_event.dart';
import 'package:guardias_escolares/core/navigation/navigation_service.dart';
import 'package:guardias_escolares/core/navigation/active_screen.dart';
import 'package:guardias_escolares/core/theme/theme.dart';

class GuardiasApp extends ConsumerWidget {
  const GuardiasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure push messaging initialized once app builds
    ref.watch(pushMessagingProvider);
    final auth = ref.watch(authViewModelProvider);
    final home = auth.maybeWhen(
      authenticated: (_) => const HomePage(),
      orElse: () => const LoginPage(),
    );
    // Listener a eventos de notificación para deep link sencillo tipo 'shift'
    ref.listen<AsyncValue<NotificationEvent>>(notificationEventsProvider, (prev, next) {
      final ev = next.asData?.value;
      if (ev == null) return;
      if (ev.type == 'shift' || ev.type == 'guardia') {
        // Interpretar día si viene en data['day'] (formato yyyy-MM-dd)
        DateTime? focusDay;
        final dayStr = ev.data['day'] as String?;
        if (dayStr != null) {
          try { focusDay = DateTime.parse(dayStr); } catch (_) {}
        }
        // Evitar navegación duplicada: si ya estamos en calendario y mismo día, no hacemos nada
        final active = ref.read(activeScreenProvider);
        if (active is ActiveCalendar && focusDay != null && active.focusDay != null && active.focusDay!.difference(focusDay).inDays == 0) {
          return;
        }
        NavigationService.instance.pushShiftCalendar(focusDay: focusDay);
        ref.read(activeScreenProvider.notifier).setCalendar(focusDay);
      } else if (ev.type == 'chat') {
        // ✅ NUEVO: Navegación directa a chat cuando usuario toca notificación
        final chatId = ev.data['chatId'] as String?;
        if (chatId != null && ev.opened) {
          final nav = NavigationService.instance.navigatorKey.currentState;
          if (nav != null) {
            nav.push(MaterialPageRoute(
              builder: (_) => ChatRoomPage(chatId: chatId),
            ));
          }
        }
      }
    });
    // Asegurar que si hubo mensaje inicial antes de montar listener, lo reprocesamos ahora
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushMessagingProvider).replayInitialEvent();
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Guardias Escolares',
      theme: AppTheme.light(),
      navigatorKey: NavigationService.instance.navigatorKey,
      home: home,
      // Rutas mínimas; añadir calendario real cuando exista.
      routes: {
        '/calendar': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments;
          DateTime? focusDay;
            if (args is DateTime) focusDay = args;
          // Marcar pantalla activa
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(activeScreenProvider.notifier).setCalendar(focusDay);
          });
          return CalendarPage(userId: null);
        },
      },
    );
  }
}
