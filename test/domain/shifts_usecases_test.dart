import 'package:flutter_test/flutter_test.dart';
import 'package:guardias_escolares/domain/shifts/entities/shift.dart';
import 'package:guardias_escolares/domain/shifts/repositories/shift_repository.dart';
import 'package:guardias_escolares/domain/shifts/usecases/get_shifts.dart';
import 'package:guardias_escolares/domain/shifts/usecases/reserve_shift.dart';

class _FakeShiftRepo implements ShiftRepository {
  final _data = <String, List<String>>{}; // dayId -> userIds
  final int capacity;
  _FakeShiftRepo({this.capacity = 1});

  String _id(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String().substring(0, 10);

  @override
  Future<void> reserve({
    required DateTime dayUtc,
    required String userId,
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    final id = _id(dayUtc);
    final list = _data[id] ?? <String>[];
    if (list.contains(userId)) return;
    if (list.length >= capacity) throw StateError('Day is full');
    list.add(userId);
    _data[id] = list;
  }

  @override
  Future<void> cancel({required DateTime dayUtc, required String userId}) async {
    final id = _id(dayUtc);
    final list = _data[id] ?? <String>[];
    list.remove(userId);
    _data[id] = list;
  }

  @override
  Future<List<Shift>> getRange(DateTime startUtc, DateTime endUtc) async {
    final res = <Shift>[];
    for (DateTime d = startUtc; !d.isAfter(endUtc); d = d.add(const Duration(days: 1))) {
      final id = _id(d);
      final list = _data[id] ?? const [];
      for (final u in list) {
        res.add(Shift(id: '$id-$u', date: DateTime.utc(d.year, d.month, d.day), userId: u, capacity: capacity));
      }
    }
    return res;
  }

  @override
  Stream<List<Shift>> watchMonth(DateTime monthStartUtc) async* {
    // Not needed for these tests
    yield const <Shift>[];
  }
}

void main() {
  group('Shifts use cases', () {
    test('ReserveShift then GetShifts returns the reservation', () async {
      final repo = _FakeShiftRepo(capacity: 1);
      final reserve = ReserveShift(repo);
      final get = GetShifts(repo);
      final day = DateTime.utc(2025, 9, 25);

      await reserve(dayUtc: day, userId: 'u1');
      final list = await get(day, day);

      expect(list.length, 1);
      expect(list.first.userId, 'u1');
    });

    test('ReserveShift enforces capacity and throws when full', () async {
      final repo = _FakeShiftRepo(capacity: 1);
      final reserve = ReserveShift(repo);
      final day = DateTime.utc(2025, 9, 25);

      await reserve(dayUtc: day, userId: 'u1');
      expect(() => reserve(dayUtc: day, userId: 'u2'), throwsA(isA<StateError>()));
    });
  });
}
