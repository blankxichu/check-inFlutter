import 'package:guardias_escolares/domain/shifts/entities/shift.dart';

abstract class ShiftRepository {
  Stream<List<Shift>> watchMonth(DateTime monthStartUtc);
  Future<List<Shift>> getRange(DateTime startUtc, DateTime endUtc);
  Future<void> reserve({required DateTime dayUtc, required String userId, DateTime? startUtc, DateTime? endUtc});
  Future<void> cancel({required DateTime dayUtc, required String userId});
}
