import 'package:flutter_test/flutter_test.dart';
import 'package:guardias_escolares/domain/attendance/entities/attendance_record.dart';
import 'package:guardias_escolares/domain/attendance/repositories/attendance_repository.dart';
import 'package:guardias_escolares/domain/attendance/usecases/register_attendance.dart';

class _FakeAttendanceRepo implements AttendanceRepository {
  final List<AttendanceRecord> saved = [];
  @override
  Future<void> save(AttendanceRecord record) async {
    saved.add(record);
  }
}

class _FakePhotoStorage implements PhotoStorageRepository {
  String? lastUserId;
  String? lastPath;
  @override
  Future<String> upload(String userId, String localFilePath) async {
    lastUserId = userId;
    lastPath = localFilePath;
    return 'https://example.com/$userId/${localFilePath.split('/').last}';
  }
}

void main() {
  test('RegisterAttendance.entrada guarda tipo entrada y sube foto si se provee', () async {
    final repo = _FakeAttendanceRepo();
    final storage = _FakePhotoStorage();
    final usecase = RegisterAttendance(repo: repo, storage: storage);

    await usecase.entrada(userId: 'u1', fotoLocalPath: '/tmp/foto.jpg');

    expect(repo.saved.length, 1);
    final rec = repo.saved.first;
    expect(rec.userId, 'u1');
    expect(rec.tipo, 'entrada');
    expect(storage.lastUserId, 'u1');
    expect(storage.lastPath, '/tmp/foto.jpg');
    expect(rec.fotoUrl, isNotNull);
  });

  test('RegisterAttendance.salida guarda tipo salida sin foto', () async {
    final repo = _FakeAttendanceRepo();
    final storage = _FakePhotoStorage();
    final usecase = RegisterAttendance(repo: repo, storage: storage);

    await usecase.salida(userId: 'u2');

    expect(repo.saved.length, 1);
    final rec = repo.saved.first;
    expect(rec.userId, 'u2');
    expect(rec.tipo, 'salida');
    expect(storage.lastUserId, isNull);
    expect(rec.fotoUrl, isNull);
  });
}
