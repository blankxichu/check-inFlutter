import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/domain/shifts/entities/shift.dart';
import 'package:guardias_escolares/presentation/viewmodels/calendar_view_model.dart';
import 'package:guardias_escolares/core/cache/hive_cache_service.dart';

class CalendarPage extends ConsumerStatefulWidget {
  final String? userId;
  const CalendarPage({super.key, this.userId});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _loadingDay = false;
  String? _errorDay;
  List<Shift> _dayShifts = [];
  final Map<String, String> _userLabelCache = {};

  @override
  void initState() {
    super.initState();
    final start = DateTime.utc(_focusedDay.year, _focusedDay.month, 1);
    Future.microtask(() => ref.read(calendarViewModelProvider.notifier).loadMonth(start));
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Si fue abierta con argumento (deep link) intentamos centrar y abrir detalle
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is DateTime) {
      // Evitar repetir si ya seleccionado
      if (_selectedDay == null || !_isSameDay(_selectedDay!, args)) {
        _focusedDay = args;
        _selectedDay = args;
        // Cargar info del día y abrir modal si es uno de mis días
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _loadDayDetail(args);
          // Mostrar modal sólo si es uno de mis días (igual que onDaySelected)
          final state = ref.read(calendarViewModelProvider);
          final id = _dayId(args);
          final isMine = state.assignedDayIds.contains(id);
          if (isMine && mounted) {
            _openDayModal(args);
          }
          setState(() {});
        });
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void dispose() {
    // Evita problemas de FocusScopeNode al cerrar la página
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarViewModelProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis guardias')),
      body: Column(
        children: [
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(state.error!, style: const TextStyle(color: Colors.red)),
            ),
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            selectedDayPredicate: (day) => _selectedDay != null &&
                _selectedDay!.year == day.year &&
                _selectedDay!.month == day.month &&
                _selectedDay!.day == day.day,
            // Solo visualización
            onDaySelected: (selectedDay, focusedDay) async {
              setState(() {
                _focusedDay = focusedDay;
                _selectedDay = selectedDay;
              });
              final id = _dayId(selectedDay);
              final isMine = state.assignedDayIds.contains(id);
              if (isMine) {
                _openDayModal(selectedDay);
              } else {
                await _loadDayDetail(selectedDay);
              }
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
              final start = DateTime.utc(focusedDay.year, focusedDay.month, 1);
              ref.read(calendarViewModelProvider.notifier).loadMonth(start);
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final id = _dayId(day);
                final occ = state.occupancy[id] ?? 0;
                    final isMine = state.assignedDayIds.contains(id);
                    return _DayCell(day: day, occupancy: occ, mine: isMine);
              },
              todayBuilder: (context, day, focusedDay) {
                final id = _dayId(day);
                final occ = state.occupancy[id] ?? 0;
                    final isMine = state.assignedDayIds.contains(id);
                    return _DayCell(day: day, occupancy: occ, mine: isMine, highlight: Colors.indigo.withValues(alpha: 0.15));
              },
              selectedBuilder: (context, day, focusedDay) {
                final id = _dayId(day);
                final occ = state.occupancy[id] ?? 0;
                    final isMine = state.assignedDayIds.contains(id);
                    return _DayCell(day: day, occupancy: occ, mine: isMine, highlight: Colors.green.withValues(alpha: 0.2));
              },
            ),
          ),
          if (state.loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                          child: Text('Los días marcados en verde son tus guardias asignadas por el administrador. El número indica cuántas personas hay asignadas ese día.'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_selectedDay != null)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildDayDetail(cs),
              ),
            ),
        ],
      ),
    );
  }

  String _dayId(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String().substring(0, 10);

  Future<void> _loadDayDetail(DateTime selectedDay) async {
    if (!mounted) return;
    setState(() {
      _loadingDay = true;
      _errorDay = null;
      _dayShifts = [];
    });
    try {
      final start = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
      final end = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
      final getShifts = ref.read(getShiftsProvider);
      final list = await getShifts(start, end);
      // Filtra por el día exacto por seguridad
      final filtered = list.where((s) => s.date.year == selectedDay.year && s.date.month == selectedDay.month && s.date.day == selectedDay.day).toList();
      if (!mounted) return;
      // Normalizar horas a local para visualización (mantener date en UTC para agrupación)
      final normalized = filtered.map((s) {
        if (s.startUtc == null || s.endUtc == null) return s;
        // Mantener id, date, userId, capacity sin cambios; sólo ajustamos a DateTime.local copy for display
        final startL = s.startUtc!; // ya se interpreta luego con .toLocal() en _fmt
        final endL = s.endUtc!;
        return Shift(
          id: s.id,
          date: s.date,
          userId: s.userId,
          capacity: s.capacity,
          startUtc: startL,
          endUtc: endL,
        );
      }).toList();
      setState(() => _dayShifts = normalized);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorDay = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingDay = false);
      }
    }
  }


  Future<String> _resolveUserLabel(String uid) async {
    if (_userLabelCache.containsKey(uid)) return _userLabelCache[uid]!;
    // cache local primero
    try {
      final cached = HiveCacheService().getUserLabel(uid);
      if (cached != null) {
        _userLabelCache[uid] = cached.toUpperCase();
        return _userLabelCache[uid]!;
      }
    } catch (_) {}
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        // Preferir mostrar solo el nombre en MAYÚSCULAS; fallback a email en MAYÚSCULAS; luego uid
        final raw = name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);
        _userLabelCache[uid] = raw.toUpperCase();
        try { await HiveCacheService().saveUserLabel(uid, raw); } catch (_) {}
        return _userLabelCache[uid]!;
      }
    } catch (_) {}
    _userLabelCache[uid] = uid;
    return uid;
  }

  Widget _buildDayDetail(ColorScheme cs) {
    // Agrupa por usuario para mostrar múltiples rangos en una sola fila
    final grouped = _groupShiftsByUser(_dayShifts);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Guardias del ${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_loadingDay)
            const Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Cargando guardias...'),
              ],
            )
          else if (_errorDay != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
              child: Text(_errorDay!, style: const TextStyle(color: Colors.red)),
            )
          else if (_dayShifts.isEmpty)
            const Text('No hay guardias asignadas para este día.')
          else
            ...grouped.map((g) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: FutureBuilder<String>(
                    future: _resolveUserLabel(g.userId),
                    builder: (context, snapshot) {
                      final label = snapshot.data ?? g.userId;
                      final ranges = g.shifts
                          .where((s) => s.startUtc != null && s.endUtc != null)
                          .map((s) => '${_fmt(s.startUtc!)} - ${_fmt(s.endUtc!)}')
                          .join(' | ');
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text('Usuario: $label'),
                        subtitle: ranges.isNotEmpty
                            ? Text('Horarios: $ranges')
                            : const Text('Sin horario específico'),
                        trailing: const Icon(Icons.schedule),
                      );
                    },
                  ),
                )),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    // Uniformar formato HH:mm (sin segundos) como en Admin
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openDayModal(DateTime day) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: _DayShiftsSheet(day: day),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final int occupancy;
  final bool mine;
  final Color? highlight;
  const _DayCell({required this.day, required this.occupancy, required this.mine, this.highlight});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
  color: (mine ? Colors.green.withValues(alpha: 0.18) : null) ?? highlight ?? cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 6,
            child: Text('${day.day}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Positioned(
            right: 8,
            bottom: 6,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: cs.primary,
              child: Text('$occupancy', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
          if (mine)
            Positioned(
              right: 6,
              top: 6,
              child: Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            ),
        ],
      ),
    );
  }
}

class _DayShiftsSheet extends ConsumerStatefulWidget {
  final DateTime day;
  const _DayShiftsSheet({required this.day});

  @override
  ConsumerState<_DayShiftsSheet> createState() => _DayShiftsSheetState();
}

class _DayShiftsSheetState extends ConsumerState<_DayShiftsSheet> {
  bool _loading = true;
  String? _error;
  List<Shift> _dayShifts = const [];
  List<Shift> _monthShifts = const [];
  List<_GroupedUserDayShifts> _groupedDay = const [];
  List<_GroupedUserDayShifts> _groupedMonth = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final getShifts = ref.read(getShiftsProvider);
      final d = widget.day;
      final startDay = DateTime.utc(d.year, d.month, d.day);
      final endDay = DateTime.utc(d.year, d.month, d.day);
      final startMonth = DateTime.utc(d.year, d.month, 1);
      final endMonth = DateTime.utc(d.year, d.month + 1, 0);
      final results = await Future.wait([
        getShifts(startDay, endDay),
        getShifts(startMonth, endMonth),
      ]);
      if (!mounted) return;
      setState(() {
        _dayShifts = results[0];
        _monthShifts = results[1];
        _groupedDay = _groupShiftsByUser(_dayShifts);
        _groupedMonth = _groupShiftsByUser(_monthShifts, includeDate: true);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
                Text('Guardias', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Día: ${_fmtDate(widget.day)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 2) else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // Día
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guardia del día', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_groupedDay.isEmpty)
                          Text('No hay guardias asignadas para este día.', style: TextStyle(color: cs.outline))
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _groupedDay.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final g = _groupedDay[i];
                              return _GroupedShiftTile(group: g);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                // Mes
                Text('Guardias del mes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_groupedMonth.isEmpty)
                  Text('No hay guardias asignadas este mes.', style: TextStyle(color: cs.outline))
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _groupedMonth.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final g = _groupedMonth[i];
                      return _GroupedShiftTile(group: g, showDate: true);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Agrupación de turnos ----
class _GroupedUserDayShifts {
  final String userId;
  final DateTime date; // día (UTC 00:00)
  final int capacity;
  final List<Shift> shifts; // todos los rangos de ese usuario para ese día
  const _GroupedUserDayShifts({required this.userId, required this.date, required this.capacity, required this.shifts});
}

List<_GroupedUserDayShifts> _groupShiftsByUser(List<Shift> list, {bool includeDate = false}) {
  if (list.isEmpty) return const [];
  final map = <String, List<Shift>>{}; // key: date-user o user
  for (final s in list) {
    final key = includeDate ? '${s.date.toIso8601String().substring(0,10)}-${s.userId}' : s.userId;
    map.putIfAbsent(key, () => []).add(s);
  }
  final grouped = <_GroupedUserDayShifts>[];
  map.forEach((k, v) {
    v.sort((a,b) => (a.startUtc ?? DateTime.utc(1970)).compareTo(b.startUtc ?? DateTime.utc(1970)));
    grouped.add(_GroupedUserDayShifts(userId: v.first.userId, date: v.first.date, capacity: v.first.capacity, shifts: v));
  });
  grouped.sort((a,b) {
    final c = a.date.compareTo(b.date);
    if (c != 0) return c;
    return a.userId.compareTo(b.userId);
  });
  return grouped;
}

class _GroupedShiftTile extends ConsumerWidget {
  final _GroupedUserDayShifts group;
  final bool showDate;
  const _GroupedShiftTile({required this.group, this.showDate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _sharedResolveUserLabel(group.userId),
      builder: (context, snap) {
        final label = snap.data ?? group.userId;
        final date = DateTime(group.date.year, group.date.month, group.date.day);
        final y = date.year.toString().padLeft(4, '0');
        final m = date.month.toString().padLeft(2, '0');
        final d = date.day.toString().padLeft(2, '0');
        final ranges = group.shifts
            .where((s) => s.startUtc != null && s.endUtc != null)
            .map((s) => _sharedTimeRange(s))
            .join(' | ');
        return ListTile(
          leading: const Icon(Icons.person),
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${showDate ? '$y-$m-$d • ' : ''}${ranges.isNotEmpty ? ranges : 'Sin horario específico'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          dense: true,
          trailing: Icon(Icons.schedule, color: cs.primary),
        );
      },
    );
  }
}

// Helpers compartidos para tiles agrupados
Future<String> _sharedResolveUserLabel(String uid) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data()!;
      final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
      final email = (data['email'] ?? '').toString().trim();
      return name.isNotEmpty ? name.toUpperCase() : (email.isNotEmpty ? email.toUpperCase() : uid);
    }
  } catch (_) {}
  return uid;
}

String _sharedTimeRange(Shift s) {
  String two(int v) => v.toString().padLeft(2, '0');
  final st = s.startUtc!.toLocal();
  final et = s.endUtc!.toLocal();
  return '${two(st.hour)}:${two(st.minute)}-${two(et.hour)}:${two(et.minute)}';
}

// Obsoleto: _ShiftTile reemplazado por agrupación; se deja vacío si alguien aún lo referencia accidentalmente.
// class _ShiftTile extends ConsumerWidget { /* deprecated */ }

// (Clase _ShiftTile eliminada tras refactor a agrupación)
