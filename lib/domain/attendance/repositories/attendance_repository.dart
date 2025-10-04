import 'package:guardias_escolares/domain/attendance/entities/attendance_record.dart';

abstract class AttendanceRepository {
  Future<void> save(AttendanceRecord record);
}

abstract class PhotoStorageRepository {
  Future<String> upload(String userId, String localPath);
}
