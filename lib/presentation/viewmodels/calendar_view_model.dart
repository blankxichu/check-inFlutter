import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/data/shifts/firestore_shift_repository.dart';
import 'package:guardias_escolares/domain/shifts/entities/shift.dart';
import 'package:guardias_escolares/domain/shifts/repositories/shift_repository.dart';
import 'package:guardias_escolares/domain/shifts/usecases/get_shifts.dart';
import 'package:guardias_escolares/domain/shifts/usecases/reserve_shift.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;

class _InMemoryShiftRepository implements ShiftRepository {
  final _data = <String, List<String>>{}; // dayId -> userIds
  final int capacity;
  _InMemoryShiftRepository() : capacity = 2;

  String _dayId(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String().substring(0, 10);

  @override
  Future<void> cancel({required DateTime dayUtc, required String userId}) async {
    final id = _dayId(dayUtc);
    final list = _data[id] ?? <String>[];
    list.remove(userId);
    _data[id] = list;
  }

  @override
  Future<List<Shift>> getRange(DateTime startUtc, DateTime endUtc) async {
    final res = <Shift>[];
    final start = DateTime.utc(startUtc.year, startUtc.month, startUtc.day);
    final end = DateTime.utc(endUtc.year, endUtc.month, endUtc.day);
    for (DateTime dt = start; !dt.isAfter(end); dt = dt.add(const Duration(days: 1))) {
      final id = _dayId(dt);
      final users = _data[id] ?? const [];
      for (final u in users) {
        res.add(Shift(id: '$id-$u', date: dt, userId: u, capacity: capacity));
      }
    }
    return res;
  }

  @override
  Future<void> reserve({
    required DateTime dayUtc,
    required String userId,
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    final id = _dayId(dayUtc);
    final list = _data[id] ?? <String>[];
    if (list.contains(userId)) return;
    if (list.length >= capacity) throw StateError('Day is full');
    list.add(userId);
    _data[id] = list;
  }

  @override
  Stream<List<Shift>> watchMonth(DateTime monthStartUtc) async* {
    // Not needed for MVP UI; returning periodic snapshot from getRange
    while (true) {
      final start = DateTime.utc(monthStartUtc.year, monthStartUtc.month, 1);
      final end = DateTime.utc(monthStartUtc.year, monthStartUtc.month + 1, 0);
      yield await getRange(start, end);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  try {
    if (Firebase.apps.isNotEmpty) {
      return FirestoreShiftRepository(db: FirebaseFirestore.instance);
    }
  } catch (_) {}
  return _InMemoryShiftRepository();
});

final getShiftsProvider = Provider<GetShifts>((ref) => GetShifts(ref.watch(shiftRepositoryProvider)));
final reserveShiftProvider = Provider<ReserveShift>((ref) => ReserveShift(ref.watch(shiftRepositoryProvider)));

class CalendarState {
  final DateTime focusedDayUtc;
  final Set<String> assignedDayIds; // yyyy-MM-dd donde el usuario tiene asignación
  final Map<String, int> occupancy; // yyyy-MM-dd -> count
  final bool loading;
  final String? error;

  const CalendarState({
    required this.focusedDayUtc,
    required this.assignedDayIds,
    required this.occupancy,
    this.loading = false,
    this.error,
  });

  CalendarState copyWith({
    DateTime? focusedDayUtc,
    Set<String>? assignedDayIds,
    Map<String, int>? occupancy,
    bool? loading,
    String? error,
  }) => CalendarState(
        focusedDayUtc: focusedDayUtc ?? this.focusedDayUtc,
        assignedDayIds: assignedDayIds ?? this.assignedDayIds,
        occupancy: occupancy ?? this.occupancy,
        loading: loading ?? this.loading,
        error: error,
      );
}

class CalendarViewModel extends Notifier<CalendarState> {
  GetShifts? _getShifts;
  ReserveShift? _reserve;
  String? _userId;

  @override
  CalendarState build() {
    _getShifts ??= ref.read(getShiftsProvider);
    _reserve ??= ref.read(reserveShiftProvider);
    // derive uid from auth state
    _userId = ref.watch(_currentUserIdProvider);
    final now = DateTime.now().toUtc();
    return CalendarState(
      focusedDayUtc: DateTime.utc(now.year, now.month, 1),
      assignedDayIds: <String>{},
      occupancy: <String, int>{},
      loading: false,
    );
  }

  Future<void> loadMonth(DateTime monthStartUtc) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final start = DateTime.utc(monthStartUtc.year, monthStartUtc.month, 1);
      final end = DateTime.utc(monthStartUtc.year, monthStartUtc.month + 1, 0);
      final list = await _getShifts!(start, end);
      final map = <String, int>{};
      final mine = <String>{};
      for (final s in list) {
        final id = _dayId(s.date);
        map[id] = (map[id] ?? 0) + 1;
        if (s.userId == _userId) mine.add(id);
      }
      state = state.copyWith(occupancy: map, assignedDayIds: mine, loading: false);
    } catch (e) {
      final msg = e.toString().contains('permission')
          ? 'No tienes permisos para ver el calendario (reglas de Firestore).'
          : e.toString();
      state = state.copyWith(loading: false, error: msg);
    }
  }

  // Ya no se permite reservar desde la app del usuario; la asignación la realiza el admin.

  String _dayId(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String().substring(0, 10);
}

final calendarViewModelProvider = NotifierProvider<CalendarViewModel, CalendarState>(
  () => CalendarViewModel(),
);

// Read current auth user id from existing auth view model
final _currentUserIdProvider = Provider<String?>((ref) {
  final state = ref.watch(auth_vm.authViewModelProvider);
  return state.maybeWhen(authenticated: (u) => u.uid, orElse: () => null);
});
