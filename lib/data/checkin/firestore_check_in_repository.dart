import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';
import 'package:guardias_escolares/domain/checkin/repositories/check_in_repository.dart';
import 'package:guardias_escolares/core/config/app_config.dart';

class FirestoreCheckInRepository implements CheckInRepository {
  final FirebaseFirestore _db;
  FirestoreCheckInRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  @override
  Future<void> saveCheckIn(CheckIn checkIn) async {
    try {
      await _db.collection('checkins').doc(checkIn.id).set({
        'userId': checkIn.userId,
        'timestamp': checkIn.timestampUtc,
        'lat': checkIn.latitude,
        'lon': checkIn.longitude,
        'type': checkIn.type == CheckInType.inEvent ? 'in' : 'out',
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('Sin permisos para registrar check-in (revisa reglas)');
      }
      rethrow;
    }
  }

  @override
  Stream<List<CheckIn>> watchUserCheckIns({
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 50,
  }) {
    final start = fromUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final end = toUtc ?? DateTime.now().toUtc();
    Query<Map<String, dynamic>> q = _db
        .collection('checkins')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('timestamp', descending: true)
        .limit(limit);
    return q.snapshots().map((snap) => snap.docs.map((d) {
          final data = d.data();
          final ts = (data['timestamp'] as Timestamp?)?.toDate().toUtc() ?? DateTime.now().toUtc();
          final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
          final lon = (data['lon'] as num?)?.toDouble() ?? 0.0;
          final typeRaw = (data['type'] ?? 'in').toString();
          final type = typeRaw == 'out' ? CheckInType.outEvent : CheckInType.inEvent;
          return CheckIn(
            id: d.id,
            userId: (data['userId'] ?? '').toString(),
            timestampUtc: ts,
            latitude: lat,
            longitude: lon,
            type: type,
          );
        }).toList());
  }

  @override
  Future<CheckIn?> getLastCheckIn(String userId) async {
    final q = await _db
        .collection('checkins')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final d = q.docs.first;
    final data = d.data();
    final ts = (data['timestamp'] as Timestamp?)?.toDate().toUtc() ?? DateTime.now().toUtc();
    final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (data['lon'] as num?)?.toDouble() ?? 0.0;
    final typeRaw = (data['type'] ?? 'in').toString();
    final type = typeRaw == 'out' ? CheckInType.outEvent : CheckInType.inEvent;
    return CheckIn(
      id: d.id,
      userId: (data['userId'] ?? '').toString(),
      timestampUtc: ts,
      latitude: lat,
      longitude: lon,
      type: type,
    );
  }

  @override
  Future<List<CheckIn>> fetchUserCheckIns({
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 1000,
  }) async {
    final start = fromUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final end = toUtc ?? DateTime.now().toUtc();
    
    try {
      // Query más simple posible para evitar invalid-argument
      Query<Map<String, dynamic>> q = _db
          .collection('checkins')
          .where('userId', isEqualTo: userId)
          .limit(limit * 2); // Sin orderBy para evitar problemas de índice
          
      final snap = await q.get();
      
      final allResults = snap.docs.map((d) {
        final data = d.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate().toUtc() ?? DateTime.now().toUtc();
        final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
        final lon = (data['lon'] as num?)?.toDouble() ?? 0.0;
        final typeRaw = (data['type'] ?? 'in').toString();
        final type = typeRaw == 'out' ? CheckInType.outEvent : CheckInType.inEvent;
        return CheckIn(
          id: d.id,
          userId: (data['userId'] ?? '').toString(),
          timestampUtc: ts,
          latitude: lat,
          longitude: lon,
          type: type,
        );
      }).where((checkIn) {
        // Filtrar rango en memoria
        return checkIn.timestampUtc.isAfter(start.subtract(Duration(seconds: 1))) && 
               checkIn.timestampUtc.isBefore(end.add(Duration(seconds: 1)));
      }).toList();
      
      // Ordenar en memoria y limitar
      allResults.sort((a, b) => a.timestampUtc.compareTo(b.timestampUtc));
      return allResults.take(limit).toList();
      
    } catch (e) {
      debugPrint('fetchUserCheckIns ERROR: $e');
      // Si la query falla, retornar lista vacía en lugar de crashear
      return <CheckIn>[];
    }
  }
}

class FirestoreGeofenceRepository implements GeofenceRepository {
  final FirebaseFirestore _db;
  final String schoolId;
  FirestoreGeofenceRepository({required this.schoolId, FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  @override
  Future<GeofenceConfig> getGeofence() async {
    try {
      final snap = await _db.collection('schools').doc(schoolId).get();
      final data = snap.data() ?? const {};
      final lat = (data['lat'] as num?)?.toDouble() ?? AppConfig.defaultSchoolLat;
      final lon = (data['lon'] as num?)?.toDouble() ?? AppConfig.defaultSchoolLon;
      final radius = (data['radius'] as num?)?.toDouble() ?? AppConfig.defaultGeofenceRadiusM;
      return GeofenceConfig(latitude: lat, longitude: lon, radiusMeters: radius);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // usar valores por defecto para no bloquear el check-in
        return GeofenceConfig(
          latitude: AppConfig.defaultSchoolLat,
          longitude: AppConfig.defaultSchoolLon,
          radiusMeters: AppConfig.defaultGeofenceRadiusM,
        );
      }
      rethrow;
    }
  }
}
