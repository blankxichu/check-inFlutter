import 'package:flutter_test/flutter_test.dart';
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';
import 'package:guardias_escolares/domain/checkin/repositories/check_in_repository.dart';
import 'package:guardias_escolares/domain/checkin/usecases/do_check_in.dart';

class _MemCheckInRepo implements CheckInRepository {
  final List<CheckIn> saved = [];
  @override
  Future<void> saveCheckIn(CheckIn checkIn) async => saved.add(checkIn);

  @override
  Stream<List<CheckIn>> watchUserCheckIns({
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 50,
  }) async* {
    yield saved.where((e) => e.userId == userId).toList();
  }

  @override
  Future<CheckIn?> getLastCheckIn(String userId) async {
    final list = saved.where((e) => e.userId == userId).toList()
      ..sort((a,b)=> b.timestampUtc.compareTo(a.timestampUtc));
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<List<CheckIn>> fetchUserCheckIns({
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 50,
  }) async {
    Iterable<CheckIn> list = saved.where((e) => e.userId == userId);
    if (fromUtc != null) list = list.where((e) => e.timestampUtc.isAfter(fromUtc));
    if (toUtc != null) list = list.where((e) => e.timestampUtc.isBefore(toUtc));
    final ordered = list.toList()..sort((a,b)=> b.timestampUtc.compareTo(a.timestampUtc));
    return ordered.take(limit).toList();
  }
}

class _FixedGeofence implements GeofenceRepository {
  final GeofenceConfig cfg;
  _FixedGeofence(this.cfg);
  @override
  Future<GeofenceConfig> getGeofence() async => cfg;
}

void main() {
  test('fake repo saves and watches', () async {
    final r = _MemCheckInRepo();
    final c = CheckIn(
      id: '1',
      userId: 'u1',
      timestampUtc: DateTime.now().toUtc(),
      latitude: 0,
      longitude: 0,
      type: CheckInType.inEvent,
    );
    await r.saveCheckIn(c);
    final list = await r.watchUserCheckIns(userId: 'u1').first;
    expect(list.length, 1);
  });

  test('DoCheckIn guarda check-in cuando está dentro del geofence', () async {
    final repo = _MemCheckInRepo();
    final geo = _FixedGeofence(const GeofenceConfig(latitude: 19.4326, longitude: -99.1332, radiusMeters: 100));
    final usecase = DoCheckIn(checkIns: repo, geofence: geo);

    // Dentro ~20m
    await usecase(userId: 'u1', latitude: 19.4328, longitude: -99.1332, nowUtc: DateTime.utc(2025, 9, 30));
    expect(repo.saved.length, 1);
  });

  test('DoCheckIn lanza error cuando está fuera del geofence', () async {
    final repo = _MemCheckInRepo();
    final geo = _FixedGeofence(const GeofenceConfig(latitude: 19.4326, longitude: -99.1332, radiusMeters: 100));
    final usecase = DoCheckIn(checkIns: repo, geofence: geo);

    // Lejos ~500m
    expect(
      () => usecase(userId: 'u1', latitude: 19.4280, longitude: -99.1332, nowUtc: DateTime.utc(2025, 9, 30)),
      throwsA(isA<StateError>()),
    );
  });
}
