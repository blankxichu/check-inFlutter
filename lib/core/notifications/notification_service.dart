import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Generador simple incremental en memoria (reinicia al relanzar app)
class _NotificationIdGenerator {
  static int _current = 100; // empezar lejos de 1 y 2 usados legacy
  static int next() {
    _current++;
    if (_current > 1000000) _current = 100; // wrap básico
    return _current;
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _fln.initialize(settings);

    if (Platform.isAndroid) {
      final androidPlugin = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      // Canales múltiples (id, nombre, descripción, importancia)
      const channels = [
        AndroidNotificationChannel(
          'guardias_default',
          'General',
          description: 'Canal general para notificaciones variadas',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'guardias_turno',
          'Alertas de Turno',
          description: 'Notificaciones críticas de asignación / cambios de guardias',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'guardias_sistema',
          'Sistema',
          description: 'Mensajes de mantenimiento y avisos del sistema',
          importance: Importance.defaultImportance,
        ),
      ];
      for (final ch in channels) {
        await androidPlugin?.createNotificationChannel(ch);
      }
    }
    _initialized = true;
  }

  Future<void> showSimple({required int id, required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'guardias_default',
      'Notificaciones',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _fln.show(id, title, body, details);
  }

  // Mostrar usando canales categorizados e ID incremental
  Future<void> showForEvent({required String channelId, required String title, required String body, String? groupKey}) async {
    final id = _NotificationIdGenerator.next();
    AndroidNotificationDetails androidDetails;
    switch (channelId) {
      case 'guardias_turno':
        androidDetails = AndroidNotificationDetails(
          channelId,
          'Alertas de Turno',
          channelDescription: 'Notificaciones críticas de guardias',
          importance: Importance.high,
          priority: Priority.high,
          groupKey: groupKey ?? channelId,
        );
        break;
      case 'guardias_sistema':
        androidDetails = const AndroidNotificationDetails(
          'guardias_sistema',
          'Sistema',
          channelDescription: 'Mensajes del sistema',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
        break;
      default:
        androidDetails = AndroidNotificationDetails(
          'guardias_default',
          'General',
          channelDescription: 'Canal general',
          importance: Importance.high,
          priority: Priority.high,
          groupKey: groupKey ?? 'guardias_default',
        );
    }
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _fln.show(id, title, body, details);
  }

  Future<void> showGroupSummary({required String channelId, required String groupKey, required String summary, int? notificationCount}) async {
    if (!Platform.isAndroid) return; // Solo Android soporta group summary estándar
    final id = _NotificationIdGenerator.next();
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'guardias_turno' ? 'Alertas de Turno' : channelId == 'guardias_sistema' ? 'Sistema' : 'General',
      channelDescription: 'Resumen agrupado',
      importance: Importance.high,
      priority: Priority.high,
      groupKey: groupKey,
      setAsGroupSummary: true,
      number: notificationCount,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _fln.show(id, 'Resumen', summary, details);
  }
}
