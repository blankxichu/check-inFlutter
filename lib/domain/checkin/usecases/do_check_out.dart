import 'dart:math' as math;
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';
import 'package:guardias_escolares/domain/checkin/repositories/check_in_repository.dart';

class DoCheckOut {
  final CheckInRepository checkIns;
  final GeofenceRepository geofence;
  const DoCheckOut({required this.checkIns, required this.geofence});

  Future<void> call({
    required String userId,
    required double latitude,
    required double longitude,
    DateTime? nowUtc,
  }) async {
    final cfg = await geofence.getGeofence();
    if (!_isInside(latitude, longitude, cfg.latitude, cfg.longitude, cfg.radiusMeters)) {
      throw StateError('Fuera del perímetro permitido');
    }
    final ts = nowUtc ?? DateTime.now().toUtc();
    final id = '${userId}_${ts.millisecondsSinceEpoch}_out';
    await checkIns.saveCheckIn(CheckIn(
      id: id,
      userId: userId,
      timestampUtc: ts,
      latitude: latitude,
      longitude: longitude,
      type: CheckInType.outEvent,
    ));
  }

  bool _isInside(double lat, double lon, double cLat, double cLon, double radiusM) {
    const R = 6371000.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(cLat - lat);
    final dLon = toRad(cLon - lon);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat)) * math.cos(toRad(cLat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final distance = R * c;
    return distance <= radiusM;
  }
}
