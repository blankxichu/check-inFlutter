import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationMetrics {
  final int received;
  final int displayed;
  final DateTime startedAt;
  const NotificationMetrics({required this.received, required this.displayed, required this.startedAt});

  NotificationMetrics copyWith({int? received, int? displayed, DateTime? startedAt}) => NotificationMetrics(
        received: received ?? this.received,
        displayed: displayed ?? this.displayed,
        startedAt: startedAt ?? this.startedAt,
      );
}

class NotificationMetricsNotifier extends Notifier<NotificationMetrics> {
  @override
  NotificationMetrics build() => NotificationMetrics(received: 0, displayed: 0, startedAt: DateTime.now());

  void incrementReceived() => state = state.copyWith(received: state.received + 1);
  void incrementDisplayed() => state = state.copyWith(displayed: state.displayed + 1);
  void reset() => state = NotificationMetrics(received: 0, displayed: 0, startedAt: DateTime.now());
}

final notificationMetricsProvider = NotifierProvider<NotificationMetricsNotifier, NotificationMetrics>(
  NotificationMetricsNotifier.new,
);
