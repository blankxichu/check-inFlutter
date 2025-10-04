import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/domain/shifts/entities/shift.dart';
import 'package:guardias_escolares/domain/shifts/repositories/shift_repository.dart';

class FirestoreShiftRepository implements ShiftRepository {
  final FirebaseFirestore _db;
  final int defaultCapacity;
  FirestoreShiftRepository({FirebaseFirestore? db, this.defaultCapacity = 2})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('shifts');

  // Document id pattern: yyyy-MM-dd
  String _dayId(DateTime utc) => utc.toIso8601String().substring(0, 10);

  DateTime _asUtcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  @override
  Stream<List<Shift>> watchMonth(DateTime monthStartUtc) {
    final start = _asUtcDay(DateTime.utc(monthStartUtc.year, monthStartUtc.month, 1));
    final end = _asUtcDay(DateTime.utc(monthStartUtc.year, monthStartUtc.month + 1, 0));
    return _col
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end)
        .snapshots()
        .handleError((e) {
          // Log y devolver stream vacío
          // ignore: avoid_print
          print('watchMonth error: $e');
        })
        .map((snap) => _mapQuery(snap));
  }

  @override
  Future<List<Shift>> getRange(DateTime startUtc, DateTime endUtc) async {
    try {
      final q = await _col
          .where('date', isGreaterThanOrEqualTo: _asUtcDay(startUtc))
          .where('date', isLessThanOrEqualTo: _asUtcDay(endUtc))
          .get();
      return _mapQuery(q);
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('getRange Firestore error: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        // Devuelve vacío para que el calendario no truene
        return <Shift>[];
      }
      rethrow;
    }
  }

  List<Shift> _mapQuery(QuerySnapshot<Map<String, dynamic>> q) {
    final res = <Shift>[];
    for (final doc in q.docs) {
      final data = doc.data();
      // Preferir fecha desde el ID del documento (yyyy-MM-dd) para evitar desfases
      DateTime date = _parseDateFromDocId(doc.id) ?? (data['date'] is Timestamp
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now());
      date = DateTime.utc(date.year, date.month, date.day);
      final users = (data['users'] is List) ? List<String>.from(data['users']) : const <String>[];
      final slots = (data['slots'] is Map<String, dynamic>) ? (data['slots'] as Map<String, dynamic>) : const <String, dynamic>{};
      final cap = (data['capacity'] as int?) ?? defaultCapacity;
      if (users.isNotEmpty) {
        for (final uid in users) {
          final slot = slots[uid];
          _appendFromSlot(res, doc.id, date, uid, cap, slot);
        }
      } else if (slots.isNotEmpty) {
        // Soporta documentos sin 'users' pero con 'slots'
        slots.forEach((uid, slot) {
          _appendFromSlot(res, doc.id, date, uid.toString(), cap, slot);
        });
      }
    }
    return res;
  }

  void _appendFromSlot(List<Shift> res, String docId, DateTime date, String uid, int cap, dynamic slot) {
    if (slot is List) {
      for (final item in slot) {
        if (item is Map<String, dynamic>) {
          final start = _coerceToDateTime(date, item['start']);
          final end = _coerceToDateTime(date, item['end']);
          res.add(Shift(id: '$docId-$uid-${res.length}', date: date, userId: uid, capacity: cap, startUtc: start, endUtc: end));
        }
      }
    } else if (slot is Map<String, dynamic>) {
      final start = _coerceToDateTime(date, slot['start']);
      final end = _coerceToDateTime(date, slot['end']);
      res.add(Shift(id: '$docId-$uid', date: date, userId: uid, capacity: cap, startUtc: start, endUtc: end));
    } else {
      res.add(Shift(id: '$docId-$uid', date: date, userId: uid, capacity: cap));
    }
  }

  DateTime? _parseDateFromDocId(String id) {
    try {
      final p = id.split('-');
      if (p.length != 3) return null;
      return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  DateTime? _coerceToDateTime(DateTime baseDayUtc, dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      // Espera formato HH:mm
      final parts = value.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        // Cambio: construimos en hora LOCAL para alinear con la vista Admin (que usa DateTime local al crear turnos).
        // Así evitamos desplazamientos (offset) al hacer toLocal() en el calendario.
        // La fecha "date" del documento sigue tratada en UTC (medianoche) sólo para queries por día/mes.
        return DateTime(baseDayUtc.year, baseDayUtc.month, baseDayUtc.day, h, m);
      }
    }
    return null;
  }

  @override
  Future<void> reserve({required DateTime dayUtc, required String userId, DateTime? startUtc, DateTime? endUtc}) async {
    final day = _asUtcDay(dayUtc);
    final id = _dayId(day);
    final ref = _col.doc(id);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{
          'date': day,
          'users': <String>[],
          'capacity': defaultCapacity,
          'slots': <String, dynamic>{},
        };
        final users = List<String>.from(data['users'] ?? const []);
        final slots = Map<String, dynamic>.from(data['slots'] ?? const <String, dynamic>{});
        final cap = (data['capacity'] as int?) ?? defaultCapacity;
        if (users.contains(userId)) return; // already reserved
        if (users.length >= cap) {
          throw StateError('Day is full');
        }
        users.add(userId);
        data['users'] = users;
        if (startUtc != null && endUtc != null) {
          slots[userId] = {
            'start': startUtc,
            'end': endUtc,
          };
          data['slots'] = slots;
        }
        tx.set(ref, data, SetOptions(merge: true));
      });
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('reserve Firestore error: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        throw StateError('Sin permisos para reservar turno.');
      }
      rethrow;
    }
  }

  @override
  Future<void> cancel({required DateTime dayUtc, required String userId}) async {
    final day = _asUtcDay(dayUtc);
    final id = _dayId(day);
    final ref = _col.doc(id);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final data = Map<String, dynamic>.from(snap.data()!);
        final users = List<String>.from(data['users'] ?? const []);
        users.remove(userId);
        data['users'] = users;
        final slots = Map<String, dynamic>.from(data['slots'] ?? const <String, dynamic>{});
        slots.remove(userId);
        data['slots'] = slots;
        tx.set(ref, data, SetOptions(merge: true));
      });
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('cancel Firestore error: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        throw StateError('Sin permisos para cancelar turno.');
      }
      rethrow;
    }
  }
}
