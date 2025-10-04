import 'package:guardias_escolares/domain/user/value_objects/user_stats.dart';
import 'package:guardias_escolares/domain/user/repositories/user_profile_repository.dart';
import 'package:guardias_escolares/domain/checkin/repositories/check_in_repository.dart';
import 'package:guardias_escolares/application/checkin/usecases/build_sessions.dart';
import 'package:guardias_escolares/application/user/usecases/ensure_profile_doc.dart';

/// Recalcula estadísticas del usuario a partir de sus check-ins recientes.
class RefreshUserStats {
  final UserProfileRepository profiles;
  final CheckInRepository checkIns;
  final BuildSessions buildSessions;
  final EnsureProfileDoc? ensure;
  RefreshUserStats({required this.profiles, required this.checkIns, required this.buildSessions, this.ensure});

  /// Recalcula en un rango (por defecto últimos 90 días) para limitar costo.
  Future<void> call(String uid, {Duration lookback = const Duration(days: 90)}) async {
    final to = DateTime.now().toUtc();
    final from = to.subtract(lookback);
    // Asegura doc antes de proceder para evitar invalid-argument por estructura irregular
    try { 
      await ensure?.call(uid: uid); 
    } catch (_) {
      // Silently continue if ensure fails
    }
  
    // Reutilizamos fetchUserCheckIns (orden asc) con límite amplio
    final events = await checkIns.fetchUserCheckIns(userId: uid, fromUtc: from, toUtc: to, limit: 20_000);
    final sessions = buildSessions(events);
    
    int totalSessions = 0; int openSessions = 0; int totalMinutes = 0;
    for (final s in sessions) {
      if (s.isComplete) {
        totalSessions++;
        totalMinutes += s.worked.inMinutes;
      } else if (s.inTs != null && s.outTs == null) {
        openSessions++;
      }
    }
    final lastCheckInAt = events.isEmpty ? null : events.map((e)=>e.timestampUtc).reduce((a,b)=> a.isAfter(b)? a: b).toUtc();
    final stats = UserStats(
      totalSessions: totalSessions,
      openSessions: openSessions,
      totalWorkedMinutes: totalMinutes,
      lastCheckInAt: lastCheckInAt,
    );
    
    await profiles.updateStats(uid, stats);
  }
}
