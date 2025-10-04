import 'dart:math' as math;
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';
import 'package:guardias_escolares/domain/checkin/repositories/check_in_repository.dart';

class DoCheckIn {
  final CheckInRepository checkIns;
  final GeofenceRepository geofence;
  const DoCheckIn({required this.checkIns, required this.geofence});

  Future<void> call({
    required String userId,
    required double latitude,
    required double longitude,
    DateTime? nowUtc,
  }) async {
    final cfg = await geofence.getGeofence();
    final inside = _isInsideGeofence(
      latitude,
      longitude,
      cfg.latitude,
      cfg.longitude,
      cfg.radiusMeters,
    );
    if (!inside) {
      throw StateError('Fuera del perímetro permitido');
    }
    final ts = nowUtc ?? DateTime.now().toUtc();
    final id = '${userId}_${ts.millisecondsSinceEpoch}';
    await checkIns.saveCheckIn(CheckIn(
      id: id,
      userId: userId,
      timestampUtc: ts,
      latitude: latitude,
      longitude: longitude,
      type: CheckInType.inEvent,
    ));
  }

  // Distancia Haversine en metros
  bool _isInsideGeofence(double lat, double lon, double cLat, double cLon, double radiusM) {
    const R = 6371000.0; // radio tierra en metros
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(cLat - lat);
    final dLon = toRad(cLon - lon);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat)) * math.cos(toRad(cLat)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final distance = R * c;
    return distance <= radiusM;
  }
}
