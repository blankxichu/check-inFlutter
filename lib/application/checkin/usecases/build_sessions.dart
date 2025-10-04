import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';

/// Sesión agregada (in -> out) en un día local.
class Session {
  final String dayId; // yyyy-MM-dd (local)
  final DateTime? inTs;
  final DateTime? outTs;
  final int inCount;
  final int outCount;
  const Session({required this.dayId, this.inTs, this.outTs, this.inCount = 0, this.outCount = 0});

  bool get isComplete => inTs != null && outTs != null && outTs!.isAfter(inTs!);
  Duration get worked => isComplete ? outTs!.difference(inTs!) : Duration.zero;
}

/// Construye sesiones a partir de eventos atómicos (CheckIn/Out) ordenados cronológicamente.
class BuildSessions {
  List<Session> call(List<CheckIn> events) {
    final byDay = <String, List<CheckIn>>{};
    for (final e in events) {
      final local = e.timestampUtc.toLocal();
      final day = '${local.year.toString().padLeft(4,'0')}-${local.month.toString().padLeft(2,'0')}-${local.day.toString().padLeft(2,'0')}';
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final sessions = <Session>[];
    final days = byDay.keys.toList()..sort();
    for (final day in days) {
      final evs = byDay[day]!..sort((a,b)=>a.timestampUtc.compareTo(b.timestampUtc));
      DateTime? openIn; int inCounter=0; int outCounter=0;
      for (final ev in evs) {
        if (ev.type == CheckInType.inEvent) {
          if (openIn != null) {
            sessions.add(Session(dayId: day, inTs: openIn, outTs: null, inCount: inCounter, outCount: outCounter));
            inCounter = 0; outCounter = 0;
          }
            openIn = ev.timestampUtc.toLocal();
            inCounter++;
        } else { // out
          outCounter++;
          if (openIn != null) {
            sessions.add(Session(dayId: day, inTs: openIn, outTs: ev.timestampUtc.toLocal(), inCount: inCounter, outCount: outCounter));
            openIn = null; inCounter = 0; outCounter = 0;
          } else {
            sessions.add(Session(dayId: day, inTs: null, outTs: ev.timestampUtc.toLocal(), inCount: 0, outCount: outCounter));
            outCounter = 0;
          }
        }
      }
      if (openIn != null) {
        sessions.add(Session(dayId: day, inTs: openIn, outTs: null, inCount: inCounter, outCount: outCounter));
      }
    }
    sessions.sort((a,b){
      final c = b.dayId.compareTo(a.dayId);
      if (c != 0) return c;
      final at = a.inTs ?? a.outTs ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.inTs ?? b.outTs ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return sessions;
  }
}
