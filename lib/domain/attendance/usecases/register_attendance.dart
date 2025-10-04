import 'package:guardias_escolares/domain/attendance/entities/attendance_record.dart';
import 'package:guardias_escolares/domain/attendance/repositories/attendance_repository.dart';

class RegisterAttendance {
  final AttendanceRepository repo;
  final PhotoStorageRepository storage;
  const RegisterAttendance({required this.repo, required this.storage});

  Future<void> entrada({
    required String userId,
    DateTime? nowUtc,
    String? fotoLocalPath,
    double? lat,
    double? lon,
  }) async {
    await _registrar('entrada', userId, nowUtc, fotoLocalPath, lat, lon);
  }

  Future<void> salida({
    required String userId,
    DateTime? nowUtc,
    String? fotoLocalPath,
    double? lat,
    double? lon,
  }) async {
    await _registrar('salida', userId, nowUtc, fotoLocalPath, lat, lon);
  }

  Future<void> _registrar(
    String tipo,
    String userId,
    DateTime? nowUtc,
    String? fotoLocalPath,
    double? lat,
    double? lon,
  ) async {
    if (tipo != 'entrada' && tipo != 'salida') {
      throw ArgumentError('Tipo inválido');
    }
    final ts = nowUtc ?? DateTime.now().toUtc();
    String? fotoUrl;
    if (fotoLocalPath != null) {
      fotoUrl = await storage.upload(userId, fotoLocalPath);
    }
    final id = '${userId}_${tipo}_${ts.millisecondsSinceEpoch}';
    await repo.save(AttendanceRecord(
      id: id,
      userId: userId,
      tipo: tipo,
      timestampUtc: ts,
      fotoUrl: fotoUrl,
      latitude: lat,
      longitude: lon,
    ));
  }
}
