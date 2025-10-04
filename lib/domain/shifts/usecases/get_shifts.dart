import 'package:guardias_escolares/domain/shifts/entities/shift.dart';
import 'package:guardias_escolares/domain/shifts/repositories/shift_repository.dart';

class GetShifts {
  final ShiftRepository repo;
  const GetShifts(this.repo);

  Future<List<Shift>> call(DateTime startUtc, DateTime endUtc) {
    return repo.getRange(startUtc, endUtc);
  }
}
