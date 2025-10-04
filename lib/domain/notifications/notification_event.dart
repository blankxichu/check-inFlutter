/// Domain model que abstrae una notificación entrante (FCM + locales)
class NotificationEvent {
  final String id; // puede ser un timestamp string o messageId
  final String? title;
  final String? body;
  final String type; // e.g. shift, checkin, system, generic
  final Map<String, dynamic> data;
  final bool opened; // true si proviene de tap (onMessageOpenedApp / initial)
  final bool foreground; // true si llegó con app en foreground

  NotificationEvent({
    required this.id,
    required this.type,
    required this.data,
    this.title,
    this.body,
    this.opened = false,
    this.foreground = false,
  });
}
