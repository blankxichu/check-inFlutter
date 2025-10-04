import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:guardias_escolares/domain/attendance/entities/attendance_record.dart';
import 'package:guardias_escolares/domain/attendance/repositories/attendance_repository.dart';

class FirestoreAttendanceRepository implements AttendanceRepository {
  final FirebaseFirestore _db;
  FirestoreAttendanceRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  @override
  Future<void> save(AttendanceRecord record) async {
    try {
      await _db.collection('attendance').doc(record.id).set({
        'userId': record.userId,
        'tipo': record.tipo,
        'timestamp': record.timestampUtc,
        'fotoUrl': record.fotoUrl,
        'lat': record.latitude,
        'lon': record.longitude,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('Sin permisos para guardar asistencia (revisa reglas)');
      }
      rethrow;
    }
  }
}

class FirebasePhotoStorageRepository implements PhotoStorageRepository {
  final FirebaseStorage _storage;
  FirebasePhotoStorageRepository({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<String> upload(String userId, String localPath) async {
    final fileName = localPath.split('/').last;
    final ref = _storage.ref().child('attendance').child(userId).child(fileName);
    try {
      await ref.putFile(File(localPath));
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw StateError('Sin permisos para subir foto (revisa reglas de Storage)');
      }
      rethrow;
    }
    return await ref.getDownloadURL();
  }
}
