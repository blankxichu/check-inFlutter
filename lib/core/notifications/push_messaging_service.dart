import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;
import 'package:guardias_escolares/domain/notifications/notification_event.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart' as crash;
import 'dart:async';
import 'notification_service.dart';
import 'package:guardias_escolares/core/navigation/active_screen.dart';
import 'package:guardias_escolares/core/notifications/notification_metrics.dart';
import 'package:hive/hive.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background: inicializamos notificaciones y mostramos usando canales.
  await NotificationService.instance.init();
  final title = message.notification?.title ?? (message.data['title'] as String? ?? 'Notificación');
  final body = message.notification?.body ?? (message.data['body'] as String? ?? '');
  // Determinar canal por tipo (si no hay type -> default)
  final type = (message.data['type'] as String?)?.toLowerCase() ?? 'generic';
  String channel;
  switch (type) {
    case 'shift':
    case 'guardia':
      channel = 'guardias_turno';
      break;
    case 'system':
    case 'sistema':
      channel = 'guardias_sistema';
      break;
    default:
      channel = 'guardias_default';
  }
  await NotificationService.instance.showForEvent(
    channelId: channel,
    title: title,
    body: body,
    groupKey: channel,
  );
}

class PushMessagingService {
  FirebaseMessaging? _fm;
  FirebaseFirestore? _db;
  final Ref ref;

  static const bool _kVerboseLogging = true;

  PushMessagingService(this.ref, {FirebaseMessaging? fm, FirebaseFirestore? db})
      : _fm = fm,
        _db = db;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  final StreamController<NotificationEvent> _events = StreamController<NotificationEvent>.broadcast();
  // Dedupe simple en memoria (últimos N ids)
  final List<String> _recentMessageIds = <String>[]; // mantiene orden de llegada
  static const int _maxRecentIds = 50;
  final Map<String, DateTime> _recentCompositeKeys = {}; // fallback dedupe (type+day)
  static const Duration _compositeDedupeWindow = Duration(seconds: 60);
  // Agrupación rápida de notificaciones shift
  final List<NotificationEvent> _recentShiftForeground = [];
  DateTime _lastGroupSummary = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _groupWindow = Duration(seconds: 25);
  static const int _groupMin = 3;
  NotificationEvent? _bufferedInitialEvent;
  bool _initialReplayed = false;

  Stream<NotificationEvent> get events => _events.stream;
  // Estado simple para evitar duplicar notificaciones si pantalla relevante activa
  // (se podría reemplazar por provider externo; aquí bandera interna opt-in)
  bool Function(NotificationEvent ev)? isRelevantScreenActive;

  Future<void> init() async {
    if (_initialized) return;
    // Evitar inicializar en tests (flutter test) o si Firebase no está listo
    final isTest = const bool.fromEnvironment('FLUTTER_TEST') ||
        (Platform.environment['FLUTTER_TEST'] == 'true');
    if (isTest) {
      _initialized = true;
      return;
    }

    if (Firebase.apps.isEmpty) {
      // Firebase no inicializado: salimos sin error para no romper UI/tests
      _initialized = true;
      return;
    }

    _fm ??= FirebaseMessaging.instance;
    try {
      await _fm!.setAutoInitEnabled(true);
      _logDebug('Auto-init habilitado para FCM');
    } catch (e, st) {
      _logError('setAutoInitEnabled', e, st, nonFatal: true);
    }
    _db ??= FirebaseFirestore.instance;

    // Background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Deep linking: mensaje que abrió la app (cold start)
    try {
      final initial = await _fm!.getInitialMessage();
      if (initial != null && !_isDuplicate(initial.messageId)) {
        _bufferedInitialEvent = _toEvent(initial, opened: true, foreground: false);
        _registerMessageId(initial.messageId);
        // NO emitimos aún; se reproducirá cuando la app haya montado listeners.
      }
    } catch (e, st) {
      _logError('Error en getInitialMessage', e, st);
    }

    // iOS permissions
    final settings = await _fm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _logDebug('Permisos FCM -> ${settings.authorizationStatus}');
    // Persist simple flag for denied so UI can show banner until user dismisses
    try {
      final box = Hive.box('app_cache');
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        box.put('notif_perm_denied', true);
      } else if (settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional) {
        box.put('notif_perm_denied', false);
      }
    } catch (_) {}

    // Foreground notifications → mostrar con notificaciones locales
    if (!Platform.isAndroid) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    FirebaseMessaging.onMessage.listen((message) async {
      if (_isDuplicate(message.messageId)) {
        // Emitimos evento ligero opcional para métricas si quieres (omitido ahora)
        return; // No mostramos ni volvemos a procesar
      }
      await NotificationService.instance.init();
      final title = message.notification?.title ?? 'Notificación';
      final body = message.notification?.body ?? (message.data['body'] as String? ?? '');
      // Evitar duplicar si UI relevante activa
      final provisionalEv = _safeBuildEvent(message, opened: false, foreground: true);
      // Métricas: recibido
      try { ref.read(notificationMetricsProvider.notifier).incrementReceived(); } catch (_) {}
      // Fallback dedupe si no hay messageId utilizando type+day
      if (provisionalEv != null && (message.messageId == null || message.messageId!.isEmpty)) {
        final compKey = _compositeKey(provisionalEv);
        if (compKey != null) {
          final now = DateTime.now();
          _cleanupComposite();
            if (_recentCompositeKeys.containsKey(compKey)) {
              return; // duplicado dentro de ventana
            }
          _recentCompositeKeys[compKey] = now;
        }
      }
      if (provisionalEv != null) {
        final skip = isRelevantScreenActive?.call(provisionalEv) == true;
        if (!skip) {
          // Canal según tipo
          final channel = _mapTypeToChannel(provisionalEv.type);
          await NotificationService.instance.showForEvent(
            channelId: channel,
            title: title,
            body: body,
            groupKey: channel,
          );
          try { ref.read(notificationMetricsProvider.notifier).incrementDisplayed(); } catch (_) {}
          _maybeBufferForGrouping(provisionalEv);
          _logDebug('Notificación foreground mostrada (type=${provisionalEv.type})');
        }
      } else {
        await NotificationService.instance.showSimple(id: 2, title: title, body: body);
        try { ref.read(notificationMetricsProvider.notifier).incrementDisplayed(); } catch (_) {}
      }
      // Emitir evento dominio foreground
      try {
        final ev = provisionalEv ?? _toEvent(message, opened: false, foreground: true);
        _emitEvent(ev, source: 'onMessage');
        _registerMessageId(message.messageId);
      } catch (e, st) {
        _logError('Error parse onMessage', e, st);
      }
    });

    // Tap en notificación (app background / terminated -> abierta)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      try {
        final ev = _toEvent(message, opened: true, foreground: false);
        _emitEvent(ev, source: 'onMessageOpenedApp');
      } catch (e, st) {
        _logError('Error parse onMessageOpenedApp', e, st);
      }
    });

    // Vincular token con el usuario autenticado
    _bindTokenToUserOnAuth();

    _initialized = true;
  }

  void _bindTokenToUserOnAuth() {
    // Guarda el token cada vez que cambia el estado de auth.
    ref.listen<auth_vm.AuthState>(
      auth_vm.authViewModelProvider,
      (prev, next) async {
        await _handleAuthState(next);
      },
      fireImmediately: true,
    );

    // También evaluar el estado actual por si el listener no recibe cambios (p.ej. usuario ya autenticado).
    Future.microtask(() => _handleAuthState(ref.read(auth_vm.authViewModelProvider)));
  }

  Future<void> _handleAuthState(auth_vm.AuthState state) async {
    if (state is! auth_vm.AuthAuthenticated) {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
    }
    await state.maybeWhen(
      authenticated: (user) async {
        try {
          final token = await _fetchTokenWithRetry();
          if (token != null) {
            _logDebug('Token FCM obtenido (${token.substring(0, 10)}...) para ${user.uid}');
            try {
              await _saveToken(user.uid, token);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('No se pudo guardar token FCM (permiso?): $e');
              }
              _logError('saveToken fallo inicial', e, null, nonFatal: true);
            }
          }
          // Suscribirse a topic global siempre
          _subscribeSafe('all');
          // Si es admin (según rol en estado auth), suscribirse a admins
          final roleStr = user.role.toString().toLowerCase();
          final isAdmin = roleStr.contains('admin');
          if (isAdmin) {
            _subscribeSafe('admins');
          } else {
            _unsubscribeSafe('admins');
          }
          await _tokenRefreshSub?.cancel();
          _tokenRefreshSub = _fm!.onTokenRefresh.listen((newToken) async {
            try {
              await _saveToken(user.uid, newToken);
              _subscribeSafe('all');
              if (isAdmin) _subscribeSafe('admins');
              _logDebug('Token FCM actualizado (${newToken.substring(0, 10)}...)');
            } catch (e, st) {
              if (kDebugMode) {
                debugPrint('No se pudo actualizar token FCM: $e');
              }
              _logError('update token refresh', e, st, nonFatal: true);
            }
          });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error obteniendo token FCM: $e');
          }
          _logError('getToken fallo', e, null, nonFatal: true);
        }
      },
      orElse: () async {},
    );
  }

  Future<String?> _fetchTokenWithRetry() async {
    const attempts = 3;
    for (var i = 1; i <= attempts; i++) {
      try {
        final token = await _fm!.getToken();
        if (token != null && token.isNotEmpty) {
          return token;
        }
        _logDebug('getToken intento $i devolvió null');
      } catch (e, st) {
        _logError('getToken intento $i', e, st, nonFatal: true);
      }
      await Future.delayed(Duration(milliseconds: 500 * i));
    }
    _logDebug('No se pudo obtener token FCM tras $attempts intentos');
    return null;
  }

  Future<void> _saveToken(String uid, String token) async {
    final data = {
      'token': token,
      'platform': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'other',
      'updatedAt': FieldValue.serverTimestamp(),
      // ✅ Campo 'uid' eliminado: redundante con la ruta users/{uid}/fcmTokens/{token}
    };
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        await _db!
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(token)
            .set(data, SetOptions(merge: true));
        if (kDebugMode) {
          debugPrint('Saved FCM token for $uid (${token.substring(0, 8)}...)');
        }
        _logDebug('Token FCM persistido para $uid (len=${token.length})');
        crash.FirebaseCrashlytics.instance.log('FCM token guardado: ${token.substring(0,8)} para $uid');
        return;
      } on FirebaseException catch (e) {
        if (kDebugMode) {
          debugPrint('Error saving FCM token: ${e.code} ${e.message}');
        }
        _logError('saveToken intento $attempts', e, null, nonFatal: true);
        // No relanzar para evitar excepciones no manejadas si las reglas lo bloquean
        if (attempts >= 2) return;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  NotificationEvent _toEvent(RemoteMessage m, {required bool opened, required bool foreground}) {
    final data = <String, dynamic>{...m.data};
    final type = (data['type'] as String?)?.toLowerCase() ?? 'generic';
    final ev = NotificationEvent(
      id: m.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: m.notification?.title ?? data['title'] as String?,
      body: m.notification?.body ?? data['body'] as String?,
      type: type,
      data: data,
      opened: opened,
      foreground: foreground,
    );
    return ev;
  }

  NotificationEvent? _safeBuildEvent(RemoteMessage m, {required bool opened, required bool foreground}) {
    try {
      return _toEvent(m, opened: opened, foreground: foreground);
    } catch (_) {
      return null;
    }
  }

  String _mapTypeToChannel(String type) {
    switch (type) {
      case 'shift':
      case 'guardia':
        return 'guardias_turno';
      case 'system':
      case 'sistema':
        return 'guardias_sistema';
      default:
        return 'guardias_default';
    }
  }

  void _emitEvent(NotificationEvent ev, {required String source}) {
    try {
      _events.add(ev);
      crash.FirebaseCrashlytics.instance.log('NotificationEvent $source type=${ev.type} opened=${ev.opened}');
    } catch (e, st) {
      _logError('emitEvent fallo', e, st, nonFatal: true);
    }
  }

  // Reproduce el evento inicial si estaba bufferizado y aún no se entregó.
  void replayInitialEvent() {
    if (_initialReplayed) return;
    if (_bufferedInitialEvent != null) {
      _emitEvent(_bufferedInitialEvent!, source: 'replayInitial');
    }
    _initialReplayed = true;
    _bufferedInitialEvent = null;
  }

  bool _isDuplicate(String? messageId) {
    if (messageId == null || messageId.isEmpty) return false; // sin id no deduplicamos
    return _recentMessageIds.contains(messageId);
  }

  void _registerMessageId(String? messageId) {
    if (messageId == null || messageId.isEmpty) return;
    _recentMessageIds.add(messageId);
    if (_recentMessageIds.length > _maxRecentIds) {
      _recentMessageIds.removeRange(0, _recentMessageIds.length - _maxRecentIds);
    }
  }

  String? _compositeKey(NotificationEvent ev) {
    final day = ev.data['day'];
    if (day is String && (ev.type == 'shift' || ev.type == 'guardia')) {
      return '${ev.type}|$day';
    }
    return null;
  }

  void _cleanupComposite() {
    final now = DateTime.now();
    _recentCompositeKeys.removeWhere((k, v) => now.difference(v) > _compositeDedupeWindow);
  }

  void _maybeBufferForGrouping(NotificationEvent ev) {
    if (!(ev.type == 'shift' || ev.type == 'guardia')) return;
    final now = DateTime.now();
    // limpiar eventos fuera de ventana
    _recentShiftForeground.removeWhere((e) => now.difference(e.opened ? now : now) > _groupWindow); // simplificado (todos usan now window)
    _recentShiftForeground.add(ev);
    if (_recentShiftForeground.length >= _groupMin && now.difference(_lastGroupSummary) > _groupWindow) {
      _showGroupSummary(now);
    }
  }

  Future<void> _showGroupSummary(DateTime now) async {
    _lastGroupSummary = now;
    final count = _recentShiftForeground.length;
    final uniqueDays = _recentShiftForeground.map((e) => e.data['day']).whereType<String>().toSet().length;
    final summary = count == 1
        ? '1 alerta de guardia'
        : '$count alertas de guardia en $uniqueDays día${uniqueDays == 1 ? '' : 's'}';
    try {
      await NotificationService.instance.showGroupSummary(
        channelId: 'guardias_turno',
        groupKey: 'guardias_turno',
        summary: summary,
        notificationCount: count,
      );
    } catch (_) {}
    _recentShiftForeground.clear();
  }

  void _logError(String ctx, Object e, StackTrace? st, {bool nonFatal = true}) {
    if (_kVerboseLogging || kDebugMode) {
      debugPrint('[PushMessagingService] $ctx -> $e');
    }
    if (nonFatal) {
      crash.FirebaseCrashlytics.instance.log('PushErr: $ctx: $e');
    } else {
      crash.FirebaseCrashlytics.instance.recordError(e, st, reason: ctx, fatal: true);
    }
  }

  void _logDebug(String message) {
    if (_kVerboseLogging || kDebugMode) {
      debugPrint('[PushMessagingService] $message');
    }
    try {
      crash.FirebaseCrashlytics.instance.log('PushDbg: $message');
    } catch (_) {}
  }

  Future<void> _subscribeSafe(String topic) async {
    try {
      await _fm?.subscribeToTopic(topic);
    } catch (e, st) {
  _logError('subscribe $topic', e, st, nonFatal: true);
    }
  }

  Future<void> _unsubscribeSafe(String topic) async {
    try {
      await _fm?.unsubscribeFromTopic(topic);
    } catch (e, st) {
  _logError('unsubscribe $topic', e, st, nonFatal: true);
    }
  }
}

final pushMessagingProvider = Provider<PushMessagingService>((ref) {
  final svc = PushMessagingService(ref);
  // Disparar init sin bloquear el build
  Future(() async {
    await NotificationService.instance.init();
    await svc.init();
  });
  // Conectar supresión automática: si ya estamos en calendario del mismo día no mostrar noti foreground
  svc.isRelevantScreenActive = (ev) {
    // Solo aplicamos a notificaciones de turnos
    if (ev.type != 'shift' && ev.type != 'guardia') return false;
    final active = ref.read(activeScreenProvider);
    if (active is ActiveCalendar) {
      final dayStr = ev.data['day'] as String?;
      if (dayStr == null || active.focusDay == null) return false;
      try {
        final evDay = DateTime.parse(dayStr);
        final a = active.focusDay!;
        return a.year == evDay.year && a.month == evDay.month && a.day == evDay.day;
      } catch (_) {
        return false;
      }
    }
    return false;
  };
  return svc;
});

// Stream provider útil para UI que quiera reaccionar a eventos de notificaciones
final notificationEventsProvider = StreamProvider<NotificationEvent>((ref) {
  final svc = ref.watch(pushMessagingProvider);
  return svc.events;
});
