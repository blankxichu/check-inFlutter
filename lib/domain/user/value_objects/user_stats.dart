/// Value object con estadísticas acumuladas del usuario.
class UserStats {
  final int totalSessions;
  final int openSessions;
  final int totalWorkedMinutes; // minutos efectivos trabajados
  final DateTime? lastCheckInAt;

  const UserStats({
    this.totalSessions = 0,
    this.openSessions = 0,
    this.totalWorkedMinutes = 0,
    this.lastCheckInAt,
  });

  UserStats copyWith({
    int? totalSessions,
    int? openSessions,
    int? totalWorkedMinutes,
    DateTime? lastCheckInAt,
  }) => UserStats(
        totalSessions: totalSessions ?? this.totalSessions,
        openSessions: openSessions ?? this.openSessions,
        totalWorkedMinutes: totalWorkedMinutes ?? this.totalWorkedMinutes,
        lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      );
}
