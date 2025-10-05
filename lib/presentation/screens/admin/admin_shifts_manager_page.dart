import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:guardias_escolares/core/cache/hive_cache_service.dart';

typedef AdminShiftDayCallback = void Function(DateTime day);
class _ShiftEditorResult {
  const _ShiftEditorResult({
    required this.day,
    required this.ranges,
    this.capacity,
  });

  final DateTime day;
  final List<ShiftInterval> ranges;
  final int? capacity;

  String get dayId => DateFormat('yyyy-MM-dd').format(day);
}

class AdminShiftsManagerPage extends StatefulWidget {
  const AdminShiftsManagerPage({super.key, this.onOpenAssignDay});

  final AdminShiftDayCallback? onOpenAssignDay;

  @override
  State<AdminShiftsManagerPage> createState() => _AdminShiftsManagerPageState();
}

class _AdminShiftsManagerPageState extends State<AdminShiftsManagerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, String> _labelCache = <String, String>{};
  final Set<String> _labelPending = <String>{};

  String? _busyEntryId;
  bool _createBusy = false;
  bool _selectionMode = false;
  bool _bulkDeleting = false;
  final Set<String> _selectedEntries = <String>{};

  static const List<String> _timeOptions = <String>[
    '06:00', '06:30', '07:00', '07:30', '08:00', '08:30',
    '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '12:00', '12:30', '13:00', '13:30', '14:00', '14:30',
    '15:00', '15:30', '16:00', '16:30', '17:00', '17:30',
    '18:00', '18:30', '19:00', '19:30', '20:00', '20:30',
    '21:00', '21:30', '22:00', '22:30', '23:00', '23:30',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar guardias'),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: 'Cancelar selección',
              icon: const Icon(Icons.close),
              onPressed: _bulkDeleting ? null : _clearSelection,
            ),
          if (_selectionMode)
            IconButton(
              tooltip: 'Eliminar seleccionadas',
              icon: _bulkDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              onPressed: !_bulkDeleting && _selectedEntries.isNotEmpty
                  ? _deleteSelectedEntries
                  : null,
            ),
          if (!_selectionMode)
            IconButton(
              tooltip: 'Seleccionar',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () {
                setState(() {
                  _selectionMode = true;
                });
              },
            ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBusy || _selectionMode ? null : _openCreateModal,
        icon: _createBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_task_outlined),
        label: const Text('Nueva guardia'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Buscar por usuario, día o horario',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar',
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchCtrl.clear(),
                        ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('shifts')
                    .orderBy('date', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _buildError(snapshot.error.toString(), theme);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = _buildEntries(snapshot.data!);
                  _preloadLabels(entries);
                  final filtered = _filterEntries(entries);
                  if (filtered.isEmpty) {
                    return _buildEmptyState(theme);
                  }
                  return RefreshIndicator(
                    onRefresh: _forceRefresh,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return _buildEntryCard(entry, theme);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final query = _searchCtrl.text.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'No hay guardias registradas'
                  : 'No se encontraron guardias para "$query"',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Error cargando guardias',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(AdminShiftEntry entry, ThemeData theme) {
    final label = _labelCache[entry.userId] ?? entry.userId;
    final subtitle = _buildSubtitle(entry);
    final isBusy = _busyEntryId == entry.uniqueId;
    final isSelected = _selectedEntries.contains(entry.uniqueId);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _selectionMode && isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.35)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          isThreeLine: true,
          leading: _selectionMode
              ? Checkbox(
                  value: isSelected,
                  shape: const CircleBorder(),
                  onChanged: (_) => _toggleEntrySelection(entry),
                )
              : CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(
                    entry.dayId.substring(8),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: _selectionMode
              ? null
              : isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : PopupMenuButton<_EntryAction>(
                      tooltip: 'Acciones',
                      onSelected: (action) => _handleEntryAction(action, entry),
                      itemBuilder: (context) => <PopupMenuEntry<_EntryAction>>[
                        const PopupMenuItem<_EntryAction>(
                          value: _EntryAction.edit,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Editar guardia'),
                          ),
                        ),
                        const PopupMenuItem<_EntryAction>(
                          value: _EntryAction.openAssignTab,
                          child: ListTile(
                            leading: Icon(Icons.calendar_month_outlined),
                            title: Text('Editar en asignador'),
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<_EntryAction>(
                          value: _EntryAction.delete,
                          child: ListTile(
                            leading: Icon(Icons.delete_forever_outlined),
                            title: Text('Eliminar guardia'),
                          ),
                        ),
                      ],
                    ),
          onTap: () {
            if (_selectionMode) {
              _toggleEntrySelection(entry);
            } else {
              _handleEntryAction(_EntryAction.edit, entry);
            }
          },
          onLongPress: () {
            if (!_selectionMode) {
              setState(() {
                _selectionMode = true;
              });
              _toggleEntrySelection(entry);
            }
          },
        ),
      ),
    );
  }

  String _buildSubtitle(AdminShiftEntry entry) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final displayDate = dateFmt.format(entry.date);
    final slots = entry.intervals;
    final schedule = slots.isEmpty
        ? 'Sin horario definido'
        : slots.map((s) => '${s.start} - ${s.end}').join(', ');
    final suffix = entry.totalAssigned > 0
        ? ' (${entry.totalAssigned}/${entry.capacity ?? entry.totalAssigned} asignados)'
        : '';
    return '$displayDate$suffix\n$schedule';
  }

  Future<void> _handleEntryAction(_EntryAction action, AdminShiftEntry entry) async {
    switch (action) {
      case _EntryAction.edit:
        await _openEditModal(entry);
        break;
      case _EntryAction.openAssignTab:
        _redirectToAssignTab(entry);
        break;
      case _EntryAction.delete:
        await _confirmDelete(entry);
        break;
    }
  }

  Future<void> _redirectToAssignTab(AdminShiftEntry entry) async {
    final callback = widget.onOpenAssignDay;
    if (callback == null) return;
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    if (!mounted) return;
    Navigator.of(context).pop();
    Future.microtask(() => callback(day));
  }

  Future<void> _confirmDelete(AdminShiftEntry entry) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final label = _labelCache[entry.userId] ?? entry.userId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar guardia'),
          content: Text('¿Eliminar la guardia de $label el ${entry.dayId}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;
    await _deleteEntry(entry);
  }

  Future<void> _deleteEntry(AdminShiftEntry entry) async {
    setState(() => _busyEntryId = entry.uniqueId);
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions.httpsCallable('assignShift').call({
        'uid': entry.userId,
        'day': entry.dayId,
        'action': 'unassign',
      });
      await _cleanupDayDocument(entry.dayId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Guardia eliminada para ${_labelCache[entry.userId] ?? entry.userId}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyEntryId = null);
      }
    }
  }

  Future<void> _openEditModal(AdminShiftEntry entry) async {
    if (!mounted) return;
    final label = _labelCache[entry.userId] ?? entry.userId;
    final result = await showModalBottomSheet<_ShiftEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _ShiftEditorSheet(
          title: 'Editar guardia',
          userLabel: label,
          initialDay: entry.date,
          initialRanges: entry.intervals,
          timeOptions: _timeOptions,
          initialCapacity: entry.capacity,
        );
      },
    );
    if (result == null) return;
    await _updateEntry(entry, result);
  }

  Future<void> _updateEntry(AdminShiftEntry entry, _ShiftEditorResult result) async {
    setState(() => _busyEntryId = entry.uniqueId);
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final newDayId = result.dayId;
      final oldDayId = entry.dayId;
      if (newDayId != oldDayId) {
        await functions.httpsCallable('assignShift').call({
          'uid': entry.userId,
          'day': oldDayId,
          'action': 'unassign',
        });
        await _cleanupDayDocument(oldDayId);
      }
      final payload = <String, dynamic>{
        'uid': entry.userId,
        'day': newDayId,
        'shifts': result.ranges
            .map((r) => <String, String>{'start': r.start, 'end': r.end})
            .toList(),
      };
      final capacityToSend = result.capacity ?? (newDayId != oldDayId ? entry.capacity : null);
      if (capacityToSend != null) {
        payload['capacity'] = capacityToSend;
      }
      await functions.httpsCallable('assignMultipleShifts').call(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Guardia actualizada – ${result.dayId} (${result.ranges.length} turno${result.ranges.length == 1 ? '' : 's'})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyEntryId = null);
      }
    }
  }

  void _toggleEntrySelection(AdminShiftEntry entry) {
    setState(() {
      if (_selectedEntries.contains(entry.uniqueId)) {
        _selectedEntries.remove(entry.uniqueId);
        if (_selectedEntries.isEmpty && _selectionMode) {
          _selectionMode = false;
        }
      } else {
        _selectedEntries.add(entry.uniqueId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedEntries.clear();
      _selectionMode = false;
    });
  }

  Future<void> _deleteSelectedEntries() async {
    if (_selectedEntries.isEmpty) return;

    final entriesMap = <String, AdminShiftEntry>{};
    final snapshot = await FirebaseFirestore.instance
        .collection('shifts')
        .orderBy('date', descending: true)
        .get();
    final allEntries = _buildEntries(snapshot);
    for (final entry in allEntries) {
      entriesMap[entry.uniqueId] = entry;
    }

    final targets = _selectedEntries
        .map((id) => entriesMap[id])
        .whereType<AdminShiftEntry>()
        .toList();
    if (targets.isEmpty) {
      _clearSelection();
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar guardias seleccionadas'),
        content: Text('¿Eliminar ${targets.length} guardia(s) seleccionadas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _bulkDeleting = true;
    });
    int success = 0;
    final List<String> errors = <String>[];
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final Set<String> affectedDays = <String>{};
    for (final entry in targets) {
      try {
        await functions.httpsCallable('assignShift').call({
          'uid': entry.userId,
          'day': entry.dayId,
          'action': 'unassign',
        });
        success++;
        affectedDays.add(entry.dayId);
      } catch (e) {
        final label = _labelCache[entry.userId] ?? entry.userId;
        errors.add('${entry.dayId} ($label): $e');
      }
    }
    for (final dayId in affectedDays) {
      await _cleanupDayDocument(dayId);
    }
    if (!mounted) return;
    setState(() {
      _bulkDeleting = false;
      _selectedEntries.clear();
      _selectionMode = false;
    });
    final message = errors.isEmpty
        ? 'Se eliminaron $success guardia(s)'
        : 'Eliminadas $success guardias. Errores: ${errors.take(3).join('; ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _cleanupDayDocument(String dayId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('shifts').doc(dayId);
      final snap = await ref.get();
      if (!snap.exists) return;
      final data = snap.data();
      final usersRaw = data?['users'];
      final users = usersRaw is Iterable
          ? usersRaw.whereType<String>().toList()
          : <String>[];
      bool hasAssignments = users.isNotEmpty;
      if (!hasAssignments) {
        final slots = data?['slots'];
        if (slots is Map<String, dynamic>) {
          hasAssignments = slots.values.any((value) {
            if (value is Iterable) {
              return value.isNotEmpty;
            }
            if (value is Map) {
              return value.isNotEmpty;
            }
            return value != null;
          });
        }
      }
      if (!hasAssignments) {
        await ref.delete();
      }
    } catch (e) {
      debugPrint('No se pudo limpiar el día $dayId: $e');
    }
  }

  Future<void> _openCreateModal() async {
    if (!mounted) return;
    final result = await showModalBottomSheet<_CreateShiftPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CreateShiftSheet(timeOptions: _timeOptions),
    );
    if (result == null) return;
    await _createEntry(result);
  }

  Future<void> _createEntry(_CreateShiftPayload payload) async {
    setState(() => _createBusy = true);
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final data = <String, dynamic>{
        'day': DateFormat('yyyy-MM-dd').format(payload.day),
        'shifts': payload.ranges
            .map((r) => <String, String>{'start': r.start, 'end': r.end})
            .toList(),
        if (payload.capacity != null) 'capacity': payload.capacity,
      };
      if (payload.mode == _TargetMode.email) {
        data['email'] = payload.identifier;
      } else {
        data['uid'] = payload.identifier;
      }
      await functions.httpsCallable('assignMultipleShifts').call(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardia creada correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la guardia: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _createBusy = false);
      }
    }
  }

  List<AdminShiftEntry> _filterEntries(List<AdminShiftEntry> entries) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries.where((entry) {
      final label = (_labelCache[entry.userId] ?? entry.userId).toLowerCase();
      final schedule = entry.intervals
          .map((e) => '${e.start}-${e.end}')
          .join(' ')
          .toLowerCase();
      final capacity = entry.capacity?.toString() ?? '';
      return label.contains(query) ||
          entry.userId.toLowerCase().contains(query) ||
          entry.dayId.toLowerCase().contains(query) ||
          schedule.contains(query) ||
          capacity.contains(query);
    }).toList();
  }

  void _preloadLabels(List<AdminShiftEntry> entries) {
    for (final entry in entries) {
      final uid = entry.userId;
      if (_labelCache.containsKey(uid) || _labelPending.contains(uid)) {
        continue;
      }
      _labelPending.add(uid);
      _resolveUserLabel(uid).then((value) {
        if (!mounted) return;
        setState(() {
          _labelCache[uid] = value;
          _labelPending.remove(uid);
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _labelCache[uid] = uid;
          _labelPending.remove(uid);
        });
      });
    }
  }

  Future<String> _resolveUserLabel(String uid) async {
    try {
      final cached = HiveCacheService().getUserLabel(uid);
      if (cached != null) return cached.toUpperCase();
    } catch (_) {}
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        final label =
            (name.isNotEmpty ? name : (email.isNotEmpty ? email : uid)).toUpperCase();
        try {
          await HiveCacheService().saveUserLabel(uid, label);
        } catch (_) {}
        return label;
      }
    } catch (_) {}
    return uid.toUpperCase();
  }

  List<AdminShiftEntry> _buildEntries(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final List<AdminShiftEntry> entries = <AdminShiftEntry>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dayId = _normalizeDayId(doc.id, data);
      final date = _dateFromDayId(dayId);
      final capacity = data['capacity'] is int ? data['capacity'] as int : null;
      final usersRaw = data['users'];
      final users = usersRaw is Iterable
          ? usersRaw
              .map((e) => (e?.toString() ?? '').trim())
              .where((value) => value.isNotEmpty)
              .toSet()
          : <String>[];
      final slotsRaw = data['slots'];
      final Map<String, dynamic> slots =
          slotsRaw is Map<String, dynamic> ? Map<String, dynamic>.from(slotsRaw) : {};
      final slotCount = slots.length;
      slots.forEach((uid, value) {
        final userId = uid.toString();
        if (userId.isEmpty) return;
        final intervals = _normalizeSlots(value);
        entries.add(
          AdminShiftEntry(
            dayId: dayId,
            date: date,
            userId: userId,
            intervals: intervals,
            capacity: capacity,
            totalAssigned: max(users.length, slotCount),
          ),
        );
      });
      for (final uid in users) {
        final exists = entries.any(
          (entry) => entry.dayId == dayId && entry.userId == uid,
        );
        if (exists) continue;
        entries.add(
          AdminShiftEntry(
            dayId: dayId,
            date: date,
            userId: uid,
            intervals: const <ShiftInterval>[],
            capacity: capacity,
            totalAssigned: max(users.length, slotCount),
          ),
        );
      }
    }
    entries.sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      return a.userId.compareTo(b.userId);
    });
    return entries;
  }

  String _normalizeDayId(String docId, Map<String, dynamic> data) {
    if (_isValidDayId(docId)) return docId;
    final date = _resolveDate(docId, data);
    if (date == null) return docId;
    return DateFormat('yyyy-MM-dd').format(date);
  }

  DateTime? _resolveDate(String docId, Map<String, dynamic> data) {
    final ts = data['date'];
    if (ts is Timestamp) {
      final utc = ts.toDate().toUtc();
      return DateTime.utc(utc.year, utc.month, utc.day);
    }
    return _tryParseDayId(docId);
  }

  DateTime _dateFromDayId(String dayId) {
    final parts = dayId.split('-');
    if (parts.length == 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.now();
  }

  bool _isValidDayId(String value) {
    return value.length == 10 && value[4] == '-' && value[7] == '-';
  }

  DateTime? _tryParseDayId(String value) {
    try {
      final parts = value.split('-');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  List<ShiftInterval> _normalizeSlots(dynamic value) {
    final List<ShiftInterval> result = <ShiftInterval>[];
    if (value is List) {
      for (final slot in value) {
        if (slot is Map) {
          final start = _coerceTime(slot['start']);
          final end = _coerceTime(slot['end']);
          if (start != null && end != null) {
            result.add(ShiftInterval(start: start, end: end));
          }
        }
      }
    } else if (value is Map) {
      final start = _coerceTime(value['start']);
      final end = _coerceTime(value['end']);
      if (start != null && end != null) {
        result.add(ShiftInterval(start: start, end: end));
      }
    }
    return result;
  }

  String? _coerceTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length >= 2) {
        final h = parts[0].padLeft(2, '0');
        final m = parts[1].padLeft(2, '0');
        return '$h:$m';
      }
      return null;
    }
    if (value is Timestamp) {
      final dt = value.toDate();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (value is DateTime) {
      final h = value.hour.toString().padLeft(2, '0');
      final m = value.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return null;
  }

  Future<void> _forceRefresh() async {
    await FirebaseFirestore.instance.collection('shifts').limit(1).get();
    if (mounted) {
      setState(() {});
    }
  }
}

class AdminShiftEntry {
  const AdminShiftEntry({
    required this.dayId,
    required this.date,
    required this.userId,
    required this.intervals,
    required this.totalAssigned,
    this.capacity,
  });

  final String dayId;
  final DateTime date;
  final String userId;
  final List<ShiftInterval> intervals;
  final int? capacity;
  final int totalAssigned;

  String get uniqueId => '$dayId|$userId';
}

class ShiftInterval {
  const ShiftInterval({required this.start, required this.end});

  final String start;
  final String end;

  ShiftInterval copyWith({String? start, String? end}) =>
      ShiftInterval(start: start ?? this.start, end: end ?? this.end);
}

enum _EntryAction { edit, openAssignTab, delete }

enum _TargetMode { email, uid }

class _CreateShiftPayload {
  const _CreateShiftPayload({
    required this.identifier,
    required this.mode,
    required this.day,
    required this.ranges,
    this.capacity,
  });

  final String identifier;
  final _TargetMode mode;
  final DateTime day;
  final List<ShiftInterval> ranges;
  final int? capacity;
}

class _ShiftEditorSheet extends StatefulWidget {
  const _ShiftEditorSheet({
    required this.title,
    required this.userLabel,
    required this.initialDay,
    required this.initialRanges,
    required this.timeOptions,
    this.initialCapacity,
  });

  final String title;
  final String userLabel;
  final DateTime initialDay;
  final List<ShiftInterval> initialRanges;
  final List<String> timeOptions;
  final int? initialCapacity;

  @override
  State<_ShiftEditorSheet> createState() => _ShiftEditorSheetState();
}

class _ShiftEditorSheetState extends State<_ShiftEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late List<ShiftInterval> _ranges;
  late TextEditingController _capacityCtrl;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _ranges = widget.initialRanges.isEmpty
        ? <ShiftInterval>[const ShiftInterval(start: '08:00', end: '10:00')]
        : widget.initialRanges.map((e) => e.copyWith()).toList();
    _capacityCtrl = TextEditingController(
      text: widget.initialCapacity != null ? '${widget.initialCapacity}' : '',
    );
    _selectedDay = DateTime(widget.initialDay.year, widget.initialDay.month, widget.initialDay.day);
  }

  @override
  void dispose() {
    _capacityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final localeTag = Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'es';
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Usuario: ${widget.userLabel}'),
                const SizedBox(height: 20),
                const _SectionTitle('Fecha'),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(DateFormat.yMMMMEEEEd(localeTag).format(_selectedDay)),
                    subtitle: Text('ID: ${DateFormat('yyyy-MM-dd').format(_selectedDay)}'),
                    trailing: TextButton(
                      onPressed: _pickDay,
                      child: const Text('Cambiar'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('Horarios'),
                const SizedBox(height: 8),
                ..._ranges.asMap().entries.map((entry) {
                  final index = entry.key;
                  final range = entry.value;
                  return _TimeRangeEditor(
                    key: ValueKey('edit_range_$index'),
                    index: index,
                    range: range,
                    timeOptions: widget.timeOptions,
                    onChanged: (updated) {
                      setState(() => _ranges[index] = updated);
                    },
                    onRemove: _ranges.length > 1
                        ? () => setState(() => _ranges.removeAt(index))
                        : null,
                  );
                }),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _ranges.add(const ShiftInterval(start: '08:00', end: '10:00'));
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar horario'),
                ),
                const SizedBox(height: 20),
                const _SectionTitle('Capacidad'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Capacidad (opcional)',
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar cambios'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.utc(2020, 1, 1),
      lastDate: DateTime.utc(2030, 12, 31),
    );
    if (selected != null) {
      setState(() {
        _selectedDay = selected;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final sanitized = _sanitizeRanges(_ranges);
    if (sanitized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Verifica que las horas no se solapen y que inicio sea menor a fin'),
        ),
      );
      return;
    }
    final capacityText = _capacityCtrl.text.trim();
    int? capacity;
    if (capacityText.isNotEmpty) {
      capacity = int.tryParse(capacityText);
      if (capacity == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capacidad inválida')), 
        );
        return;
      }
    }
    Navigator.of(context).pop(
      _ShiftEditorResult(
        day: DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day),
        ranges: sanitized,
        capacity: capacity,
      ),
    );
  }
}

class _TimeRangeEditor extends StatelessWidget {
  const _TimeRangeEditor({
    super.key,
    required this.index,
    required this.range,
    required this.timeOptions,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final ShiftInterval range;
  final List<String> timeOptions;
  final ValueChanged<ShiftInterval> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Turno ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Eliminar turno',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    color: Theme.of(context).colorScheme.error,
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: range.start,
                    items: timeOptions
                        .map((time) =>
                            DropdownMenuItem(value: time, child: Text(time)))
                        .toList(),
                    decoration: const InputDecoration(labelText: 'Inicio'),
                    onChanged: (value) {
                      if (value == null) return;
                      onChanged(range.copyWith(start: value));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: range.end,
                    items: timeOptions
                        .map((time) =>
                            DropdownMenuItem(value: time, child: Text(time)))
                        .toList(),
                    decoration: const InputDecoration(labelText: 'Fin'),
                    onChanged: (value) {
                      if (value == null) return;
                      onChanged(range.copyWith(end: value));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Text(
      label,
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _CreateShiftSheet extends StatefulWidget {
  const _CreateShiftSheet({required this.timeOptions});

  final List<String> timeOptions;

  @override
  State<_CreateShiftSheet> createState() => _CreateShiftSheetState();
}

class _CreateShiftSheetState extends State<_CreateShiftSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _identifierCtrl;
  late TextEditingController _capacityCtrl;
  DateTime _selectedDay = DateTime.now();
  _TargetMode _mode = _TargetMode.email;
  late List<ShiftInterval> _ranges;

  @override
  void initState() {
    super.initState();
    _identifierCtrl = TextEditingController();
    _capacityCtrl = TextEditingController();
    _ranges = <ShiftInterval>[const ShiftInterval(start: '08:00', end: '10:00')];
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final localeTag = Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'es';
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Nueva guardia', style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<_TargetMode>(
                  segments: const <ButtonSegment<_TargetMode>>[
                    ButtonSegment(
                      value: _TargetMode.email,
                      icon: Icon(Icons.email_outlined),
                      label: Text('Email'),
                    ),
                    ButtonSegment(
                      value: _TargetMode.uid,
                      icon: Icon(Icons.perm_identity),
                      label: Text('UID'),
                    ),
                  ],
                  selected: <_TargetMode>{_mode},
                  onSelectionChanged: (selection) {
                    setState(() => _mode = selection.first);
                  },
                ),
                const SizedBox(height: 20),
                const _SectionTitle('Identificador'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _identifierCtrl,
                  decoration: InputDecoration(
                    labelText:
                        _mode == _TargetMode.email ? 'Email del usuario' : 'UID del usuario',
                    prefixIcon: Icon(_mode == _TargetMode.email
                        ? Icons.email_outlined
                        : Icons.perm_identity),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Campo obligatorio';
                    }
                    if (_mode == _TargetMode.email && !value.contains('@')) {
                      return 'Ingresa un email válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const _SectionTitle('Fecha'),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(DateFormat.yMMMMEEEEd(localeTag).format(_selectedDay)),
                    subtitle: Text('ID: ${DateFormat('yyyy-MM-dd').format(_selectedDay)}'),
                    trailing: TextButton(
                      onPressed: _pickDate,
                      child: const Text('Cambiar'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('Horarios'),
                const SizedBox(height: 8),
                ..._ranges.asMap().entries.map((entry) {
                  final index = entry.key;
                  final range = entry.value;
                  return _TimeRangeEditor(
                    key: ValueKey('create_range_$index'),
                    index: index,
                    range: range,
                    timeOptions: widget.timeOptions,
                    onChanged: (updated) {
                      setState(() => _ranges[index] = updated);
                    },
                    onRemove: _ranges.length > 1
                        ? () => setState(() => _ranges.removeAt(index))
                        : null,
                  );
                }),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _ranges.add(const ShiftInterval(start: '08:00', end: '10:00'));
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar horario'),
                ),
                const SizedBox(height: 20),
                const _SectionTitle('Capacidad'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Capacidad (opcional)',
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Crear guardia'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.utc(2020, 1, 1),
      lastDate: DateTime.utc(2030, 12, 31),
    );
    if (selected != null) {
      setState(() => _selectedDay = selected);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final sanitized = _sanitizeRanges(_ranges);
    if (sanitized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Verifica que las horas no se solapen y que inicio sea menor a fin'),
        ),
      );
      return;
    }
    final capacityText = _capacityCtrl.text.trim();
    int? capacity;
    if (capacityText.isNotEmpty) {
      capacity = int.tryParse(capacityText);
    }
    Navigator.of(context).pop(
      _CreateShiftPayload(
        identifier: _identifierCtrl.text.trim(),
        mode: _mode,
        day: _selectedDay,
        ranges: sanitized,
        capacity: capacity,
      ),
    );
  }
}

List<ShiftInterval>? _sanitizeRanges(List<ShiftInterval> ranges) {
  final List<ShiftInterval> sanitized = ranges
      .map((r) => ShiftInterval(start: r.start, end: r.end))
      .where((r) => r.start.isNotEmpty && r.end.isNotEmpty)
      .toList();
  if (sanitized.isEmpty) return null;

  final converted = sanitized
      .map((r) => _RangeMinutes(_hhmmToMinutes(r.start), _hhmmToMinutes(r.end)))
      .toList();
  for (final range in converted) {
    if (range.start == null || range.end == null || range.start! >= range.end!) {
      return null;
    }
  }
  converted.sort((a, b) => a.start!.compareTo(b.start!));
  for (var i = 1; i < converted.length; i++) {
    if (converted[i].start! < converted[i - 1].end!) {
      return null;
    }
  }
  return sanitized;
}

int? _hhmmToMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

@visibleForTesting
List<ShiftInterval>? sanitizeIntervalsForTesting(List<ShiftInterval> ranges) =>
    _sanitizeRanges(ranges);

@visibleForTesting
int? hhmmToMinutesForTesting(String value) => _hhmmToMinutes(value);

class _RangeMinutes {
  const _RangeMinutes(this.start, this.end);

  final int? start;
  final int? end;
}
