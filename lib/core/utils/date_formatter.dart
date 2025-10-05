import 'package:intl/intl.dart';

/// Formateador de fechas para mostrar timestamps de mensajes de forma amigable
class ChatDateFormatter {
  /// Formatea una fecha para mostrar en mensajes de chat
  /// - Si es hoy: muestra solo la hora (ej: "14:30")
  /// - Si es ayer: muestra "Ayer 14:30"
  /// - Si es esta semana: muestra día de la semana y hora (ej: "Lun 14:30")
  /// - Si es más antiguo: muestra fecha completa (ej: "12 Sep 14:30")
  static String formatMessageTime(DateTime messageDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay = DateTime(messageDate.year, messageDate.month, messageDate.day);
    
    final timeFormat = DateFormat('HH:mm');
    final time = timeFormat.format(messageDate);

    // Hoy: solo hora
    if (messageDay == today) {
      return time;
    }
    
    // Ayer
    if (messageDay == yesterday) {
      return 'Ayer $time';
    }
    
    // Esta semana (últimos 7 días)
    final daysAgo = today.difference(messageDay).inDays;
    if (daysAgo < 7) {
      final dayFormat = DateFormat('E', 'es_ES'); // Lun, Mar, etc.
      final day = dayFormat.format(messageDate);
      return '$day $time';
    }
    
    // Más antiguo: fecha completa
    final dateFormat = DateFormat('d MMM', 'es_ES');
    final date = dateFormat.format(messageDate);
    return '$date $time';
  }

  /// Formatea una fecha para separadores de grupo en el chat
  /// - Si es hoy: "Hoy"
  /// - Si es ayer: "Ayer"
  /// - Si es esta semana: día de la semana completo (ej: "Lunes")
  /// - Si es más antiguo: fecha completa (ej: "12 de septiembre")
  static String formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay = DateTime(date.year, date.month, date.day);

    if (messageDay == today) {
      return 'Hoy';
    }
    
    if (messageDay == yesterday) {
      return 'Ayer';
    }
    
    // Esta semana (últimos 7 días)
    final daysAgo = today.difference(messageDay).inDays;
    if (daysAgo < 7) {
      final dayFormat = DateFormat('EEEE', 'es_ES'); // Lunes, Martes, etc.
      return dayFormat.format(date);
    }
    
    // Más antiguo: fecha completa
    final dateFormat = DateFormat('d \'de\' MMMM', 'es_ES');
    return dateFormat.format(date);
  }
}
