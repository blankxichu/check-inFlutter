import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';

abstract class CheckInRepository {
  Future<void> saveCheckIn(CheckIn checkIn);
  Stream<List<CheckIn>> watchUserCheckIns({
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit,
  });
  Future<CheckIn?> getLastCheckIn(String userId);
  Future<List<CheckIn>> fetchUserCheckIns({
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit,
  });
}

abstract class GeofenceRepository {
  Future<GeofenceConfig> getGeofence();
}

class GeofenceConfig {
  final double latitude;
  final double longitude;
  final double radiusMeters;
  const GeofenceConfig({required this.latitude, required this.longitude, required this.radiusMeters});
}
