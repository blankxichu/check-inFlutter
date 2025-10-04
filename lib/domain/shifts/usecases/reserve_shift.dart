import 'package:guardias_escolares/domain/shifts/repositories/shift_repository.dart';

class ReserveShift {
  final ShiftRepository repo;
  const ReserveShift(this.repo);

  Future<void> call({required DateTime dayUtc, required String userId, DateTime? startUtc, DateTime? endUtc}) {
    return repo.reserve(dayUtc: dayUtc, userId: userId, startUtc: startUtc, endUtc: endUtc);
  }
}
