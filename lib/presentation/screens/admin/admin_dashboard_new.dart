import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:guardias_escolares/domain/shifts/entities/shift.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io' show Platform, File; // para fallback
import 'package:path_provider/path_provider.dart';
import 'package:guardias_escolares/presentation/viewmodels/admin_view_model.dart';
import 'package:hive_flutter/hive_flutter.dart' as hive;
import 'package:firebase_crashlytics/firebase_crashlytics.dart' as crash;
import 'package:flutter/foundation.dart';
import 'package:guardias_escolares/core/cache/hive_cache_service.dart';
import 'package:guardias_escolares/presentation/screens/admin/admin_shifts_manager_page.dart';

// Callback global simple para abrir la pestaña "Asignar Guardias" con un día preseleccionado
typedef AdminEditDayRequest = void Function(DateTime day);
AdminEditDayRequest? adminEditDayRequest;

// Clase para manejar horarios de turnos
class ShiftTime {
  final String start;
  final String end;
  
  ShiftTime({required this.start, required this.end});
  
  @override
  String toString() => '$start - $end';
}

class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_NewAssignShiftFormState> _assignKey = GlobalKey<_NewAssignShiftFormState>();

  @override
  void initState() {
    super.initState();
  _tabController = TabController(length: 4, vsync: this);
    // Registrar callback global para abrir "Asignar Guardias" con el día elegido
    adminEditDayRequest = (DateTime day) {
      try {
        _tabController.index = 0; // pestaña Asignar Guardias
        // Delegar al formulario para seleccionar el día
        _assignKey.currentState?.selectDay(day);
        // Intenta nuevamente tras el frame por si el widget aún no se ha montado
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _assignKey.currentState?.selectDay(day);
        });
      } catch (_) {}
    };
  }

  @override
  void dispose() {
    // Asegura limpiar el foco antes de destruir el árbol para evitar FocusScopeNode disposed
    try {
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {}
    // Limpia el callback global
    adminEditDayRequest = null;
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Por ahora simplificamos la verificación de admin
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard - Nueva Interfaz'),
        actions: [
          IconButton(
            tooltip: 'Gestionar guardias',
            icon: const Icon(Icons.delete_outline),
            onPressed: _openShiftsManager,
          ),
          IconButton(
            tooltip: 'Estado',
            icon: const Icon(Icons.info_outline),
            onPressed: _openStatusSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Asignar Guardias'),
            Tab(text: 'Ver Asignaciones'),
            Tab(text: 'Check-ins'),
            Tab(text: 'Usuarios'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NewAssignShiftForm(key: _assignKey),
          const _AssignmentsView(),
          _CheckInsView(),
          const _UsersAdminView(),
        ],
      ),
    );
  }

  void _openShiftsManager() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminShiftsManagerPage(
          onOpenAssignDay: (day) => adminEditDayRequest?.call(day),
        ),
      ),
    );
  }
}

extension _AdminStatus on _AdminDashboardPageState {
  void _openStatusSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final fsPersistence = FirebaseFirestore.instance.settings.persistenceEnabled ?? false;
        final hiveOpen = hive.Hive.isBoxOpen('app_cache');

        Future<bool> checkCrashlytics() async {
          try {
            await crash.FirebaseCrashlytics.instance.setCustomKey('status_probe', DateTime.now().toIso8601String());
            await crash.FirebaseCrashlytics.instance.log('status panel probe');
            return true;
          } catch (_) {
            return false;
          }
        }

        Widget statusRow({required Color color, required String label, required bool enabled}) {
          final cs = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: enabled ? Colors.green : cs.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          );
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.3,
          minChildSize: 0.2,
          maxChildSize: 0.6,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    Row(
                      children: [
                        Text('Estado', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        )
                      ],
                    ),
                    const SizedBox(height: 4),
                    statusRow(color: Colors.green, label: 'Firestore offline: ${fsPersistence ? 'enabled' : 'disabled'}', enabled: fsPersistence),
                    FutureBuilder<bool>(
                      future: checkCrashlytics(),
                      builder: (context, snap) {
                        final ok = snap.data == true;
                        return statusRow(color: Colors.green, label: 'Crashlytics: ${ok ? 'enabled' : 'disabled'}', enabled: ok);
                      },
                    ),
                    statusRow(color: Colors.green, label: 'Cache local (Hive): ${hiveOpen ? 'app_cache abierto' : 'cerrado'}', enabled: hiveOpen),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.outbox),
                          label: const Text('Enviar log de prueba'),
                          onPressed: () async {
                            try {
                              await crash.FirebaseCrashlytics.instance.log('Test log manual desde panel de estado');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log enviado')));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error enviando log: $e')));
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        if (kDebugMode)
                          TextButton(
                            onPressed: () => throw Exception('Test exception for Crashlytics'),
                            child: const Text('Throw Test Exception'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Nueva interfaz simplificada para asignar guardias
class _NewAssignShiftForm extends ConsumerStatefulWidget {
  const _NewAssignShiftForm({super.key});

  @override
  ConsumerState<_NewAssignShiftForm> createState() => _NewAssignShiftFormState();
}

// Vista de Check-ins: filtrar por fecha y usuario, y ver check-ins de hoy
class _CheckInsView extends ConsumerStatefulWidget {
  const _CheckInsView();

  @override
  ConsumerState<_CheckInsView> createState() => _CheckInsViewState();
}

// Vista de administración de usuarios: buscar por email y asignar rol
class _UsersAdminView extends ConsumerStatefulWidget {
  const _UsersAdminView();

  @override
  ConsumerState<_UsersAdminView> createState() => _UsersAdminViewState();
}

class _UsersAdminViewState extends ConsumerState<_UsersAdminView> {
  final TextEditingController _emailCtrl = TextEditingController();
  String? _resolvedUid;
  String? _role; // 'admin' | 'parent'
  bool? _blocked; // estado de bloqueo
  bool? _deleted; // estado de eliminado (soft delete)
  String? _error;
  bool _loading = false;

  // Listado paginado de últimos usuarios
  static const int _pageSize = 20;
  bool _listLoading = false;
  bool _listHasMore = true;
  String _listOrderField = 'lastLoginAt';
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _userDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastUserDoc;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialUsers();
  }

  Future<void> _lookup() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _loading = true; _error = null; _resolvedUid = null; _role = null; _blocked = null; _deleted = null; });
    try {
      final qs = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (qs.docs.isEmpty) {
        setState(() { _error = 'Usuario no encontrado'; _loading = false; });
        return;
      }
      final doc = qs.docs.first;
      final data = doc.data();
      setState(() {
        _resolvedUid = doc.id;
        _role = (data['role'] as String?)?.toLowerCase() == 'admin' ? 'admin' : 'parent';
        _blocked = data['blocked'] == true;
        _deleted = data['deleted'] == true;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setRole(String role) async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(adminViewModelProvider.notifier).setRoleByEmail(email, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rol actualizado a $role')));
      await _lookup();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Administrar usuarios', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email del usuario',
                    hintText: 'persona@correo.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: _loading ? null : _lookup, icon: const Icon(Icons.search), label: const Text('Buscar')),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          if (_resolvedUid != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_role == 'admin' ? Icons.shield : Icons.person, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _emailCtrl.text.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'UID: $_resolvedUid',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Rol actual: ${_role ?? '-'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text((_role ?? '-').toUpperCase()),
                          backgroundColor: cs.secondaryContainer,
                          labelStyle: TextStyle(color: cs.onSecondaryContainer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loading ? null : () => _setRole('parent'),
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Parent'),
                        ),
                        FilledButton.icon(
                          onPressed: _loading ? null : () => _setRole('admin'),
                          icon: const Icon(Icons.shield),
                          label: const Text('Admin'),
                        ),
                        if (_deleted == true)
                          const Chip(label: Text('ELIMINADO'), backgroundColor: Colors.redAccent, labelStyle: TextStyle(color: Colors.white)),
                        if (_deleted != true) ...[
                          ElevatedButton.icon(
                            onPressed: _loading || _blocked == null ? null : () => _toggleBlockUser(_blocked!, uid: _resolvedUid),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _blocked == true ? Colors.orange : Colors.blueGrey,
                            ),
                            icon: Icon(_blocked == true ? Icons.lock_open : Icons.lock),
                            label: Text(_blocked == true ? 'Desbloquear' : 'Bloquear'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _loading ? null : () => _confirmDeleteUser(uid: _resolvedUid, email: _emailCtrl.text.trim()),
                            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Eliminar'),
                          ),
                        ],
                      ],
                    ),
                    if (_blocked != null || _deleted != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_blocked != null)
                            Chip(
                              label: Text(_blocked == true ? 'BLOQUEADO' : 'ACTIVO'),
                              backgroundColor: _blocked == true ? Colors.red.shade100 : Colors.green.shade100,
                              labelStyle: TextStyle(color: _blocked == true ? Colors.red.shade800 : Colors.green.shade800),
                            ),
                          const SizedBox(width: 8),
                          if (_deleted == true)
                            const Chip(
                              label: Text('ELIMINADO'),
                              backgroundColor: Colors.black26,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Últimos usuarios', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_listLoading && _userDocs.isEmpty) const LinearProgressIndicator(minHeight: 2),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _userDocs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final d = _userDocs[index];
              final data = d.data();
              final email = (data['email'] ?? '').toString();
              final name = (data['displayName'] ?? '').toString();
              final role = (data['role'] ?? 'parent').toString();
              final blocked = data['blocked'] == true;
              return ListTile(
                leading: Icon(blocked ? Icons.lock : (role == 'admin' ? Icons.shield : Icons.person), color: blocked ? Colors.redAccent : cs.primary),
                title: Text(
                  (blocked ? '[BLOQUEADO] ' : '') + (name.isNotEmpty ? name : email),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: blocked ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                ),
                subtitle: Text('UID: ${d.id}\n$email', maxLines: 2, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v){
                    if (v == 'select') { _emailCtrl.text = email; _lookup(); }
                    else if (v == 'block') { _toggleBlockUser(blocked, uid: d.id); }
                    else if (v == 'delete') { _confirmDeleteUser(uid: d.id, email: email); }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'select', child: Text('Ver / Editar')),
                    PopupMenuItem(value: 'block', child: Text(blocked ? 'Desbloquear' : 'Bloquear')),
                    const PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.redAccent))),
                  ],
                  child: Chip(
                    label: Text(role.toUpperCase()),
                    backgroundColor: blocked ? Colors.red.shade100 : cs.secondaryContainer,
                    labelStyle: TextStyle(color: blocked ? Colors.red.shade800 : cs.onSecondaryContainer),
                  ),
                ),
                onTap: () {
                  _emailCtrl.text = email;
                  _lookup();
                },
              );
            },
          ),
          if (_listHasMore) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: _listLoading ? null : _loadMoreUsers,
                icon: const Icon(Icons.expand_more),
                label: Text(_listLoading ? 'Cargando...' : 'Ver más (+$_pageSize)'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Nota: Se respeta siempre admin para laraxichu@gmail.com.', style: TextStyle(color: cs.outline)),
        ],
      ),
    );
  }

  Future<void> _loadInitialUsers() async {
    setState(() {
      _userDocs.clear();
      _lastUserDoc = null;
      _listHasMore = true;
    });
    await _loadMoreUsers();
  }

  Future<void> _loadMoreUsers() async {
    if (!_listHasMore || _listLoading) return;
    setState(() { _listLoading = true; });
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('users')
          .orderBy(_listOrderField, descending: true)
          .limit(_pageSize);
      if (_lastUserDoc != null) {
        q = q.startAfterDocument(_lastUserDoc!);
      }
      final snap = await q.get();
      if (snap.docs.isEmpty) {
        setState(() { _listHasMore = false; });
      } else {
        setState(() {
          _userDocs.addAll(snap.docs);
          _lastUserDoc = snap.docs.last;
          if (snap.docs.length < _pageSize) _listHasMore = false;
        });
      }
    } on FirebaseException catch (_) {
      // Fallback a 'createdAt' si no existe 'lastLoginAt'
      if (_listOrderField == 'lastLoginAt') {
        setState(() { _listOrderField = 'createdAt'; });
        return _loadMoreUsers();
      } else if (_listOrderField == 'createdAt') {
        setState(() { _listOrderField = 'email'; });
        return _loadMoreUsers();
      } else {
        setState(() { _listHasMore = false; });
      }
    } finally {
      if (mounted) {
        setState(() { _listLoading = false; });
      }
    }
  }

  // --- NUEVAS FUNCIONES: bloquear / desbloquear / eliminar usuario ---
  Future<void> _toggleBlockUser(bool currentlyBlocked, {String? uid}) async {
    final targetUid = uid ?? _resolvedUid;
    if (targetUid == null) return;
    try {
      setState(() { _loading = true; });
      await FirebaseFirestore.instance.collection('users').doc(targetUid).set({
        'blocked': !currentlyBlocked,
        'blockedUpdatedAt': DateTime.now(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(!currentlyBlocked ? 'Usuario bloqueado' : 'Usuario desbloqueado')),
      );
      // Refresh card if it's the selected one
      if (uid == null) await _lookup();
      // Refresh list silently
      await _refreshListSilent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar bloqueo: $e')),
      );
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _confirmDeleteUser({String? uid, String? email}) async {
    final targetUid = uid ?? _resolvedUid;
    if (targetUid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar definitivamente al usuario${email != null ? ' $email' : ''}? Esto no elimina sus check-ins.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Eliminar'),
            ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      setState(() { _loading = true; });
      // Soft delete: marcar eliminado para preservar integridad referencial
      await FirebaseFirestore.instance.collection('users').doc(targetUid).set({
        'deleted': true,
        'deletedAt': DateTime.now(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario marcado como eliminado (soft delete)')),
      );
      if (uid == null) {
        // Limpiar tarjeta de detalle si era el seleccionado
        setState(() { _resolvedUid = null; _role = null; });
      }
      await _refreshListSilent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _refreshListSilent() async {
    // Pequeño refresco sin perder el paginado actual: recargar los primeros items donde pueden estar los cambios.
    try {
      final firstBatch = await FirebaseFirestore.instance
          .collection('users')
          .orderBy(_listOrderField, descending: true)
          .limit(_userDocs.length.clamp(5, 50))
          .get();
      if (!mounted) return;
      setState(() {
        _userDocs.removeRange(0, _userDocs.length.clamp(0, firstBatch.docs.length));
        _userDocs.insertAll(0, firstBatch.docs);
      });
    } catch (_) {
      // silencioso
    }
  }
}

class _CheckInsViewState extends ConsumerState<_CheckInsView> {
  final TextEditingController _userCtrl = TextEditingController(); // email o UID
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  bool _loading = false;
  String? _error;
  int _todayCount = 0;
  final List<_CheckInRow> _rows = [];
  final Map<String, String> _userLabelCache = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = _startOfDayLocal(now);
    _to = _endOfDayLocal(now);
    _loadTodayCount();
    _runSearch();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTodayCount() async {
    try {
      final now = DateTime.now().toUtc();
      final start = DateTime.utc(now.year, now.month, now.day);
      final end = DateTime.utc(now.year, now.month, now.day, 23, 59, 59, 999);
      final qs = await FirebaseFirestore.instance
          .collection('checkins')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      if (!mounted) return;
      setState(() => _todayCount = qs.docs.length);
    } catch (_) {
      // silencioso
    }
  }

  DateTime _startOfDayLocal(DateTime d) => DateTime(d.year, d.month, d.day, 0, 0, 0);
  DateTime _endOfDayLocal(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  Future<void> _pickFrom() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    setState(() {
      _from = _startOfDayLocal(pickedDate);
      if (_from.isAfter(_to)) {
        _to = _endOfDayLocal(pickedDate);
      }
    });
  }

  Future<void> _pickTo() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    setState(() {
      _to = _endOfDayLocal(pickedDate);
      if (_to.isBefore(_from)) {
        _from = _startOfDayLocal(pickedDate);
      }
    });
  }

  Future<String?> _resolveUid(String input) async {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('@')) {
      // Parece UID
      return s;
    }
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: s)
          .limit(1)
          .get();
      if (qs.docs.isNotEmpty) return qs.docs.first.id;
    } catch (_) {}
    return null;
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
    });
    try {
  final fromUtc = _startOfDayLocal(_from).toUtc();
  final toUtc = _endOfDayLocal(_to).toUtc();
      final uid = await _resolveUid(_userCtrl.text);
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('checkins')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(fromUtc))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(toUtc));
      if (uid != null && uid.isNotEmpty) {
        q = q.where('userId', isEqualTo: uid);
      }
      // Ordenar por timestamp desc si es posible; si falla por índice, reintentar sin orderBy
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      try {
        final QuerySnapshot<Map<String, dynamic>> qs = await q.orderBy('timestamp', descending: true).limit(200).get();
        docs = qs.docs;
      } on FirebaseException catch (_) {
        final QuerySnapshot<Map<String, dynamic>> qs = await q.limit(200).get();
        docs = qs.docs;
      }
      final result = <_CheckInRow>[];
      for (final d in docs) {
        final data = d.data();
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final userId = (data['userId'] ?? '').toString();
        final lat = (data['lat'] as num?)?.toDouble();
        final lon = (data['lon'] as num?)?.toDouble();
        final type = (data['type'] ?? 'in').toString(); // 'in' | 'out'
        if (ts == null || userId.isEmpty) continue;
        result.add(_CheckInRow(id: d.id, userId: userId, timestampUtc: ts.toUtc(), latitude: lat, longitude: lon, type: type));
      }
      if (!mounted) return;
      setState(() {
        _rows.addAll(result);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<String> _labelFor(String uid) async {
    // Cache local primero
    final cache = HiveCacheService();
    final cached = cache.getUserLabel(uid);
    if (cached != null) return cached;
    if (_userLabelCache.containsKey(uid)) return _userLabelCache[uid]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        final label = name.isNotEmpty ? '$name${email.isNotEmpty ? ' <$email>' : ''}' : (email.isNotEmpty ? email : uid);
        _userLabelCache[uid] = label;
        // Escribe en cache local para uso offline
        try { await cache.saveUserLabel(uid, label); } catch (_) {}
        return label;
      }
    } catch (_) {}
    _userLabelCache[uid] = uid;
    return uid;
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _from = _startOfDayLocal(now);
      _to = _endOfDayLocal(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            runSpacing: 8,
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text('Check-ins hoy: $_todayCount'),
                onSelected: (_) {
                  _setToday();
                  _runSearch();
                },
                selected: false,
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Usuario (email o UID)',
                    hintText: 'ej. persona@correo.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              Wrap(
                runSpacing: 8,
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.calendar_today), label: Text('Desde ${_fmtDate(_from)}')),
                  TextButton.icon(onPressed: _pickTo, icon: const Icon(Icons.calendar_month), label: Text('Hasta ${_fmtDate(_to)}')),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _loading ? null : _runSearch,
                icon: const Icon(Icons.search),
                label: const Text('Buscar'),
              ),
              ElevatedButton.icon(
                onPressed: _rows.isEmpty ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Exportar PDF'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Buscando check-ins...'),
            ])
          else if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : Builder(
                      builder: (context) {
                        final aggregated = _aggregateRows(_rows);
                        return ListView.separated(
                          itemCount: aggregated.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final a = aggregated[index];
                            return FutureBuilder<String>(
                              future: _labelFor(a.userId),
                              builder: (context, snap) {
                                final label = snap.data ?? a.userId;
                                final cs2 = Theme.of(context).colorScheme;
                                String fmt(DateTime dt) {
                                  final l = dt.toLocal();
                                  return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
                                }
                final dur = a.inTs != null && a.outTs != null && a.outTs!.isAfter(a.inTs!)
                  ? _humanDuration(a.outTs!.difference(a.inTs!))
                                    : null;
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: cs2.secondaryContainer,
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: cs2.onSecondaryContainer,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text(a.day, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            if (a.inTs != null) ...[
                                              const Icon(Icons.arrow_circle_right, color: Colors.green, size: 18),
                                              Text(fmt(a.inTs!)),
                                            ],
                                            if (a.outTs != null) ...[
                                              const Icon(Icons.arrow_circle_left, color: Colors.green, size: 18),
                                              Text(fmt(a.outTs!)),
                                            ],
                                            if (dur != null)
                                              Text(dur, style: TextStyle(color: cs2.onSurfaceVariant, fontSize: 12)),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'in:${a.inCount}  out:${a.outCount}',
                                          style: TextStyle(color: cs2.outline, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  isThreeLine: true,
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: 'Eliminar sesión',
                                    onPressed: () => _confirmDeleteSession(a),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    try {
      final aggregated = _aggregateRows(_rows);
      if (aggregated.isEmpty) return;
      final doc = pw.Document();
      final title = 'Reporte Check-ins (${_fmtDate(_from)} a ${_fmtDate(_to)})';
      final tableHeaders = ['Usuario','Día','Entrada','Salida','Duración','In','Out'];
      final labelMap = <String,String>{};
      for (final a in aggregated) {
        labelMap[a.userId] = await _labelFor(a.userId);
      }
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              data: [
                for (final a in aggregated)
                  [
                    labelMap[a.userId] ?? a.userId,
                    a.day,
                    a.inTs == null ? '' : _fmtTime(a.inTs!),
                    a.outTs == null ? '' : _fmtTime(a.outTs!),
                    (a.inTs!=null && a.outTs!=null && a.outTs!.isAfter(a.inTs!)) ? _humanDuration(a.outTs!.difference(a.inTs!)) : '',
                    a.inCount.toString(),
                    a.outCount.toString(),
                  ]
              ],
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
              cellHeight: 20,
            ),
            pw.SizedBox(height: 12),
            pw.Text('Generado: ${DateTime.now().toLocal()}'),
          ],
        ),
      );
      final bytes = await doc.save();
      bool attemptedPrint = false;
      try {
        // Evita llamar en plataformas sin soporte (ej: web ya maneja, pero chequeamos) 
        if (!Platform.isLinux && !Platform.isWindows) { // printing soporta Android/iOS/macOS/Web
          await Printing.layoutPdf(
            onLayout: (format) async => bytes,
            name: 'reporte_checkins_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
          attemptedPrint = true;
        }
      } catch (e) {
        // Capturamos MissingPluginException y hacemos fallback
        attemptedPrint = false;
      }
      if (!attemptedPrint) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/reporte_checkins_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final f = File(filePath);
        await f.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF guardado en archivo temporal:\n$filePath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exportando PDF: $e')),
      );
    }
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
  }

  Future<void> _confirmDeleteSession(_AggRow session) async {
    if (!mounted) return;
    final count = session.eventIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar sesión'),
        content: Text('¿Eliminar esta sesión con $count evento(s)? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in session.eventIds) {
        batch.delete(FirebaseFirestore.instance.collection('checkins').doc(id));
      }
      await batch.commit();
      if (!mounted) return;
      setState(() {
        _rows.removeWhere((r) => session.eventIds.contains(r.id));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sesión eliminada (${session.eventIds.length} evento(s))')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando: $e')),
      );
    }
  }
}

class _CheckInRow {
  final String id;
  final String userId;
  final DateTime timestampUtc;
  final double? latitude;
  final double? longitude;
  final String type; // 'in' or 'out'
  _CheckInRow({required this.id, required this.userId, required this.timestampUtc, this.latitude, this.longitude, required this.type});
}

class _AggRow {
  final String userId;
  final String day; // yyyy-MM-dd local
  final DateTime? inTs;
  final DateTime? outTs;
  final int inCount;
  final int outCount;
  final List<String> eventIds;
  _AggRow({required this.userId, required this.day, this.inTs, this.outTs, this.inCount = 0, this.outCount = 0, required this.eventIds});
}

List<_AggRow> _aggregateRows(List<_CheckInRow> rows) {
  final byUserDay = <String, List<_CheckInRow>>{};
  for (final r in rows) {
    final local = r.timestampUtc.toLocal();
    final day = '${local.year.toString().padLeft(4,'0')}-${local.month.toString().padLeft(2,'0')}-${local.day.toString().padLeft(2,'0')}';
    final key = '${r.userId}__$day';
    byUserDay.putIfAbsent(key, () => []).add(r);
  }
  final sessions = <_AggRow>[];
  for (final entry in byUserDay.entries) {
    final parts = entry.key.split('__');
    final userId = parts[0];
    final day = parts[1];
    final events = entry.value..sort((a,b)=>a.timestampUtc.compareTo(b.timestampUtc));
    DateTime? openIn;
    List<String> openIds = [];
    int inCounter = 0;
    int outCounter = 0;
    for (final ev in events) {
      if (ev.type == 'in') {
        if (openIn != null) {
          // cerrar sesión incompleta previa
            sessions.add(_AggRow(userId: userId, day: day, inTs: openIn, outTs: null, inCount: inCounter+1, outCount: outCounter, eventIds: List<String>.from(openIds)));
            inCounter = 0; outCounter = 0; openIds.clear();
        }
        openIn = ev.timestampUtc;
        inCounter += 1;
        openIds.add(ev.id);
      } else { // out
        outCounter += 1;
        if (openIn != null) {
          final ids = List<String>.from(openIds)..add(ev.id);
          sessions.add(_AggRow(userId: userId, day: day, inTs: openIn, outTs: ev.timestampUtc, inCount: inCounter, outCount: outCounter, eventIds: ids));
          openIn = null;
          inCounter = 0; outCounter = 0; openIds.clear();
        } else {
          // out sin in
          sessions.add(_AggRow(userId: userId, day: day, inTs: null, outTs: ev.timestampUtc, inCount: 0, outCount: outCounter, eventIds: [ev.id]));
          outCounter = 0;
        }
      }
    }
    if (openIn != null) {
      sessions.add(_AggRow(userId: userId, day: day, inTs: openIn, outTs: null, inCount: inCounter, outCount: outCounter, eventIds: List<String>.from(openIds)));
    }
  }
  sessions.sort((a,b){
    final c = b.day.compareTo(a.day);
    if (c != 0) return c;
    final u = a.userId.compareTo(b.userId);
    if (u != 0) return u;
    final at = a.inTs ?? a.outTs ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.inTs ?? b.outTs ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  });
  return sessions;
}

String _humanDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}


class _NewAssignShiftFormState extends ConsumerState<_NewAssignShiftForm> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _capacityCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _resolvedUid;
  Timer? _debounceTimer;
  DateTime _focusedDay = DateTime.now();

  // Estados del calendario
  final Set<String> _allOccupiedDays = <String>{};
  final Set<String> _userAssignedDays = <String>{};
  // Multi‑day selection support
  final Set<String> _selectedDays = <String>{};
  final Map<String, int> _dayShiftCounts = <String, int>{};

  // Lista de turnos para el día seleccionado
  final List<ShiftTime> _dayShifts = [];

  // Horarios predefinidos para combobox
  final List<String> _timeOptions = [
    '06:00', '06:30', '07:00', '07:30', '08:00', '08:30', '09:00', '09:30',
    '10:00', '10:30', '11:00', '11:30', '12:00', '12:30', '13:00', '13:30',
    '14:00', '14:30', '15:00', '15:30', '16:00', '16:30', '17:00', '17:30',
    '18:00', '18:30', '19:00', '19:30', '20:00', '20:30', '21:00', '21:30',
    '22:00', '22:30', '23:00', '23:30'
  ];

  @override
  void initState() {
    super.initState();
    _loadAllOccupiedDays(_focusedDay);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _emailCtrl.dispose();
    _capacityCtrl.dispose();
    try { FocusManager.instance.primaryFocus?.unfocus(); } catch (_) {}
    super.dispose();
  }

  bool _isLikelyCompleteEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return false;
    final at = e.indexOf('@');
    if (at <= 0) return false; // necesita algo antes de @
    final domain = e.substring(at + 1);
    if (!domain.contains('.')) return false; // necesita . en el dominio
    if (domain.startsWith('.') || domain.endsWith('.')) return false;
    return true;
  }

  String _dayId(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  // Permite seleccionar un día desde otras pestañas (e.g., Ver Asignaciones)
  void selectDay(DateTime day) {
    // API externa (desde otras pestañas) mantiene comportamiento de single select
    final id = _dayId(day);
    setState(() {
      _focusedDay = day;
      _selectedDays
        ..clear()
        ..add(id);
      _dayShifts.clear();
    });
    _loadAllOccupiedDays(day);
    final email = _emailCtrl.text.trim();
    if (_isLikelyCompleteEmail(email)) {
      _loadUserAssignedDays(email, day);
    }
  }

  // 1. Cargar todos los días ocupados para el mes enfocado
  Future<void> _loadAllOccupiedDays(DateTime monthFocus) async {
    try {
      final firstDay = DateTime.utc(monthFocus.year, monthFocus.month, 1);
      final lastDay = DateTime.utc(monthFocus.year, monthFocus.month + 1, 0);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('shifts')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(lastDay))
          .get();

      setState(() {
        _allOccupiedDays.clear();
        _dayShiftCounts.clear();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          // Preferir ID del doc si está en formato yyyy-MM-dd; fallback a timestamp en UTC
          final idDate = _tryParseDocIdAsDate(doc.id);
          String? id;
          if (idDate != null) {
            id = _dayId(idDate);
          } else {
            final ts = data['date'];
            if (ts is Timestamp) {
              final dUtc = ts.toDate().toUtc();
              id = _dayId(dUtc);
            }
          }
          if (id == null) continue;
          _allOccupiedDays.add(id);
          _dayShiftCounts[id] = _countShiftsInDocAssign(data);
        }
      });
    } catch (e) {
      setState(() => _error = 'Error cargando días ocupados: $e');
    }
  }

  int _countShiftsInDocAssign(Map<String, dynamic> data) {
    int total = 0;
    final slots = data['slots'];
    if (slots is Map<String, dynamic>) {
      slots.forEach((_, value) {
        if (value is List) {
          total += value.length;
        } else if (value is Map<String, dynamic>) {
          total += 1;
        }
      });
    }
    if (total == 0) {
      final users = data['users'];
      if (users is List) total = users.length;
    }
    return total;
  }

  DateTime? _tryParseDocIdAsDate(String id) {
    try {
      final p = id.split('-');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  // 2. Buscar usuario por email y cargar sus días asignados
  void _onEmailChanged(String email) {
    _debounceTimer?.cancel();
    if (email.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _userAssignedDays.clear();
        _resolvedUid = null;
        _error = null;
      });
      return;
    }
    // No dispares búsqueda ni muestres error hasta que el email luzca completo
    if (!_isLikelyCompleteEmail(email)) {
      if (!mounted) return;
      setState(() {
        _userAssignedDays.clear();
        _resolvedUid = null;
        _error = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      await _loadUserAssignedDays(email.trim(), _focusedDay);
    });
  }

  Future<void> _loadUserAssignedDays(String email, DateTime monthFocus) async {
    try {
      final f = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = f.httpsCallable('getAssignedDaysForUserMonth');
      final result = await callable.call({
        'email': email,
        'year': monthFocus.year,
        'month': monthFocus.month,
      });
      
      final data = result.data as Map<String, dynamic>;
      final uid = data['uid'] as String?;
      final assignedDays = (data['assignedDays'] as List<dynamic>?)?.cast<String>() ?? [];
      
      if (!mounted) return;
      setState(() {
        _resolvedUid = uid;
        _userAssignedDays.clear();
        _userAssignedDays.addAll(assignedDays);
        _error = null;
      });
    } catch (e) {
      // Si falló la búsqueda con un email que luce válido, informa sin ruido
      if (_isLikelyCompleteEmail(email)) {
        if (!mounted) return;
        setState(() {
          _resolvedUid = null;
          _userAssignedDays.clear();
          _error = 'Usuario no encontrado';
        });
      } else {
        // Si por alguna razón llegó aquí con email incompleto, no muestres error
        if (!mounted) return;
        setState(() {
          _resolvedUid = null;
          _userAssignedDays.clear();
          _error = null;
        });
      }
    }
  }

  // 3. Seleccionar día del calendario
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final dayId = _dayId(selectedDay);
    final canSelect = !_allOccupiedDays.contains(dayId) || _userAssignedDays.contains(dayId);
    if (!canSelect) return; // ignorar días ocupados de otros usuarios
    setState(() {
      _focusedDay = focusedDay;
      if (_selectedDays.contains(dayId)) {
        _selectedDays.remove(dayId);
      } else {
        _selectedDays.add(dayId);
      }
      // Si la selección resultante quedó vacía, limpiar turnos definidos (no tiene sentido sin días)
      if (_selectedDays.isEmpty) {
        _dayShifts.clear();
      }
    });
  }

  // 4. Agregar nuevo turno
  void _addNewShift() {
    setState(() {
      _dayShifts.add(ShiftTime(start: '08:00', end: '10:00'));
    });
  }

  // 5. Remover turno
  void _removeShift(int index) {
    setState(() {
      _dayShifts.removeAt(index);
    });
  }

  // 6. Actualizar horario de turno
  void _updateShiftTime(int index, String field, String value) {
    setState(() {
      if (field == 'start') {
        _dayShifts[index] = ShiftTime(start: value, end: _dayShifts[index].end);
      } else {
        _dayShifts[index] = ShiftTime(start: _dayShifts[index].start, end: value);
      }
    });
  }

  // 7. Confirmar asignación
  Future<void> _confirmAssignment() async {
    if (_selectedDays.isEmpty || _dayShifts.isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Selecciona uno o más días, agrega al menos un turno y especifica el email');
      return;
    }

    // Validar horarios
    for (final shift in _dayShifts) {
      if (!_validateTimeRange(shift.start, shift.end)) {
        setState(() => _error = 'Hora de inicio debe ser menor que hora de fin en: ${shift.toString()}');
        return;
      }
    }

    // Mostrar confirmación
  final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final f = FirebaseFunctions.instanceFor(region: 'us-central1');
  // Revertir: siempre usar assignMultipleShifts por cada día seleccionado
  final callable = f.httpsCallable('assignMultipleShifts');
  final shifts = _dayShifts.map((s) => {'start': s.start, 'end': s.end}).toList();
      final capText = _capacityCtrl.text.trim();
      int? capacity;
      if (capText.isNotEmpty) {
        final c = int.tryParse(capText);
        if (c != null && c > 0) capacity = c;
      }

      int success = 0;
      final List<String> failures = [];
      for (final day in _selectedDays) {
        final payload = {
          'email': _emailCtrl.text.trim(),
          'day': day,
          'shifts': shifts,
          if (capacity != null) 'capacity': capacity,
        };
        try {
          debugPrint('[assignMultipleShifts][revert-multi] sending $payload');
          final resp = await callable.call(payload);
          debugPrint('[assignMultipleShifts][revert-multi] ok ${resp.data}');
          success++;
        } catch (e) {
          failures.add('$day: ${e.toString()}');
        }
      }

      if (mounted) {
        if (failures.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Guardias asignadas en $success día(s)')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Asignadas $success. Fallos en ${failures.length}: ${failures.take(3).join(', ')}')),
          );
        }
        setState(() {
          _dayShifts.clear();
          _selectedDays.clear();
        });
        await _loadAllOccupiedDays(_focusedDay);
        if (_emailCtrl.text.trim().isNotEmpty) {
          await _loadUserAssignedDays(_emailCtrl.text.trim(), _focusedDay);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _validateTimeRange(String start, String end) {
    try {
      final startParts = start.split(':');
      final endParts = end.split(':');
      final startHour = int.parse(startParts[0]);
      final startMin = int.parse(startParts[1]);
      final endHour = int.parse(endParts[0]);
      final endMin = int.parse(endParts[1]);
      
      final startTotalMin = startHour * 60 + startMin;
      final endTotalMin = endHour * 60 + endMin;
      
      return startTotalMin < endTotalMin;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Asignación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Usuario: ${_emailCtrl.text.trim()}'),
              if (_selectedDays.length == 1)
                Text('Día: ${_selectedDays.first}')
              else
                Text('Días (${_selectedDays.length}): ${_selectedDays.take(5).join(', ')}${_selectedDays.length>5 ? '...' : ''}'),
              const SizedBox(height: 8),
              const Text('Horarios:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._dayShifts.map((shift) => Text('• $shift')),
              const SizedBox(height: 12),
              const Text('¿Confirmar asignación?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Campo de email
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email del usuario',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            onChanged: _onEmailChanged,
          ),
          
          const SizedBox(height: 16),
          
          // Indicador de usuario encontrado
          if (_resolvedUid != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text('Usuario encontrado (${_userAssignedDays.length} días asignados)'),
                ],
              ),
            ),
          
          // Error
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          // 2. Calendario
          const Text('Selecciona un día:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TableCalendar<String>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              selectedDayPredicate: (day) => _selectedDays.contains(_dayId(day)),
              onDaySelected: _onDaySelected,
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
                // Recargar ocupación y asignaciones del usuario para el mes visible
                _loadAllOccupiedDays(focusedDay);
                final email = _emailCtrl.text.trim();
                if (_isLikelyCompleteEmail(email)) {
                  _loadUserAssignedDays(email, focusedDay);
                } else {
                  setState(() { _userAssignedDays.clear(); });
                }
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  final dayId = _dayId(day);
                  final isOccupied = _allOccupiedDays.contains(dayId);
                  final isUserAssigned = _userAssignedDays.contains(dayId);
                  final count = _dayShiftCounts[dayId] ?? 0;

                  Color? bgColor;
                  Color textColor = Colors.black;

                  if (isUserAssigned) {
                    bgColor = Colors.blue.shade200;
                    textColor = Colors.white;
                  } else if (isOccupied) {
                    bgColor = Colors.orange.shade200;
                  } else {
                    bgColor = Colors.green.shade200;
                  }

                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isUserAssigned ? Colors.white : Colors.deepOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: isUserAssigned ? Colors.deepPurple : Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  final dayId = _dayId(day);
                  final count = _dayShiftCounts[dayId] ?? 0;
                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.deepPurple, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Leyenda
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildLegendItem(Colors.green.shade200, 'Disponible'),
              _buildLegendItem(Colors.orange.shade200, 'Ocupado'),
              _buildLegendItem(Colors.blue.shade200, 'Mis asignaciones'),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 3. Panel de turnos (solo si hay día seleccionado)
          if (_selectedDays.isNotEmpty) _buildShiftPanel(),

          // Chips de días seleccionados
          if (_selectedDays.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedDays.map((d) => Chip(
                label: Text(d),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() {
                    _selectedDays.remove(d);
                    if (_selectedDays.isEmpty) _dayShifts.clear();
                  });
                },
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],
          
          const SizedBox(height: 16),
          
          // 4. Campo de capacidad y botón
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _capacityCtrl,
                decoration: const InputDecoration(
                  labelText: 'Capacidad (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _confirmAssignment,
                icon: _loading 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
                label: const Text('Confirmar Asignación'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildShiftPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                _selectedDays.length == 1
                  ? 'Turnos para ${_selectedDays.first}'
                  : 'Turnos (${_selectedDays.length} días seleccionados)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
              ElevatedButton.icon(
                onPressed: _addNewShift,
                icon: const Icon(Icons.add),
                label: const Text('Agregar Turno'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (_dayShifts.isEmpty)
            const Center(
              child: Text(
                'No hay turnos. Presiona "Agregar Turno" para comenzar.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ..._dayShifts.asMap().entries.map((entry) {
              final index = entry.key;
              final shift = entry.value;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Turno ${index + 1}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          if (_dayShifts.length > 1)
                            IconButton(
                              onPressed: () => _removeShift(index),
                              icon: const Icon(Icons.delete, color: Colors.red),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Hora inicio
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: shift.start,
                              decoration: const InputDecoration(
                                labelText: 'Inicio',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: _timeOptions.map((time) => DropdownMenuItem(
                                value: time,
                                child: Text(time),
                              )).toList(),
                              onChanged: (value) => _updateShiftTime(index, 'start', value!),
                            ),
                          ),
                          
                          const SizedBox(width: 12),
                          
                          // Hora fin
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: shift.end,
                              decoration: const InputDecoration(
                                labelText: 'Fin',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: _timeOptions.map((time) => DropdownMenuItem(
                                value: time,
                                child: Text(time),
                              )).toList(),
                              onChanged: (value) => _updateShiftTime(index, 'end', value!),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// Vista de asignaciones (sin cambios significativos)
class _AssignmentsView extends ConsumerStatefulWidget {
  const _AssignmentsView();

  @override
  ConsumerState<_AssignmentsView> createState() => _AssignmentsViewState();
}

class _AssignmentsViewState extends ConsumerState<_AssignmentsView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Set<String> _occupiedDays = <String>{};
  final Map<String, int> _dayShiftCounts = {};

  String _dayId(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 0, 0, 0);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _loadMonthAssignedDays(_focusedDay);
  }

  Future<void> _loadMonthAssignedDays(DateTime monthFocus) async {
    try {
      final firstDay = DateTime(monthFocus.year, monthFocus.month, 1);
      final lastDay = DateTime(monthFocus.year, monthFocus.month + 1, 0);
      final snapshot = await FirebaseFirestore.instance
          .collection('shifts')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(lastDay))
          .get();

      final days = <String>{};
      final counts = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // 1) Preferir ID del documento (yyyy-MM-dd) para evitar corrimientos por zona horaria
        final idDate = _tryParseDocIdAsDate(doc.id);
        String? id;
        if (idDate != null) {
          id = _dayId(idDate);
        } else {
          // 2) Fallback: usar Timestamp convertido a UTC para evitar off-by-one
          final rawDate = data['date'];
          if (rawDate is Timestamp) {
            final dUtc = rawDate.toDate().toUtc();
            id = _dayId(dUtc);
          }
        }
        if (id == null) continue;
        days.add(id);
        counts[id] = _countShiftsInDoc(data);
      }
      if (mounted) {
        setState(() {
          _occupiedDays
            ..clear()
            ..addAll(days);
          _dayShiftCounts
            ..clear()
            ..addAll(counts);
        });
      }
    } catch (_) {
      // silencioso en esta vista
    }
  }

  DateTime? _tryParseDocIdAsDate(String id) {
    try {
      final parts = id.split('-');
      if (parts.length != 3) return null;
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  int _countShiftsInDoc(Map<String, dynamic> data) {
    int total = 0;
    final slots = data['slots'];
    if (slots is Map<String, dynamic>) {
      slots.forEach((uid, value) {
        if (value is List) {
          total += value.length;
        } else if (value is Map<String, dynamic>) {
          total += 1; // un único slot por usuario (modelo antiguo)
        }
      });
    }
    if (total == 0) {
      final users = data['users'];
      if (users is List) total = users.length; // sin horarios, cuenta usuarios
    }
    return total;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) async {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });

    // Cargar turnos del día seleccionado desde Firestore (por rango de fecha)
    try {
      final q = await FirebaseFirestore.instance
          .collection('shifts')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(selectedDay)))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(selectedDay)))
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        // Fallback: leer por ID directo
        await _loadByDocId(selectedDay);
      } else {
        final doc = q.docs.first;
        final data = doc.data();
        final slots = data['slots'] as Map<String, dynamic>? ?? {};
        var shifts = _extractShiftsFromSlots(doc.id, selectedDay, slots);
        if (shifts.isEmpty) {
          final users = (data['users'] as List<dynamic>?) ?? const [];
          shifts = _extractShiftsFromUsers(doc.id, selectedDay, users);
        }

        if (mounted) {
          final id = _dayId(selectedDay);
          setState(() {
            if (shifts.isNotEmpty) {
              _occupiedDays.add(id);
              _dayShiftCounts[id] = shifts.length;
            }
          });
        }
      }
    } catch (e) {
      // Fallback adicional por ID; si también falla, muestra error
      try {
        await _loadByDocId(selectedDay);
      } catch (e2) {
        // silencioso; el modal mostrará su propio estado
      }
    } finally {
      // Abrir modal 3/4 con detalle del día y del mes (como en sección Calendario)
      _openDayModal(selectedDay);
    }
  }

  Future<void> _loadByDocId(DateTime selectedDay) async {
    final dayId = _dayId(selectedDay);
    final doc = await FirebaseFirestore.instance.collection('shifts').doc(dayId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final slots = data['slots'] as Map<String, dynamic>? ?? {};
    var shifts = _extractShiftsFromSlots(doc.id, selectedDay, slots);
    if (shifts.isEmpty) {
      final users = (data['users'] as List<dynamic>?) ?? const [];
      shifts = _extractShiftsFromUsers(doc.id, selectedDay, users);
    }
    if (mounted) {
      final id = _dayId(selectedDay);
      if (shifts.isNotEmpty) {
        setState(() {
          _occupiedDays.add(id);
          _dayShiftCounts[id] = shifts.length;
        });
      }
    }
  }

  List<Shift> _extractShiftsFromSlots(String docId, DateTime day, Map<String, dynamic> slots) {
    final shifts = <Shift>[];
    slots.forEach((uid, value) {
      final userSlots = value;
      if (userSlots is List) {
        for (final slot in userSlots) {
          if (slot is Map<String, dynamic>) {
            final start = slot['start'];
            final end = slot['end'];
            final startStr = start is String ? start : (start is Timestamp ? _formatTsToHHmm(start) : null);
            final endStr = end is String ? end : (end is Timestamp ? _formatTsToHHmm(end) : null);
            shifts.add(Shift(
              id: '$docId-$uid',
              date: day,
              userId: uid,
              startUtc: startStr != null ? _parseTimeToUtc(day, startStr) : null,
              endUtc: endStr != null ? _parseTimeToUtc(day, endStr) : null,
            ));
          }
        }
      } else if (userSlots is Map<String, dynamic>) {
        // Soporta modelo antiguo: un único slot por usuario
        final start = userSlots['start'];
        final end = userSlots['end'];
        final startStr = start is String ? start : (start is Timestamp ? _formatTsToHHmm(start) : null);
        final endStr = end is String ? end : (end is Timestamp ? _formatTsToHHmm(end) : null);
        shifts.add(Shift(
          id: '$docId-$uid',
          date: day,
          userId: uid,
          startUtc: startStr != null ? _parseTimeToUtc(day, startStr) : null,
          endUtc: endStr != null ? _parseTimeToUtc(day, endStr) : null,
        ));
      }
    });
    return shifts;
  }

  String _formatTsToHHmm(Timestamp ts) {
    final d = ts.toDate();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  List<Shift> _extractShiftsFromUsers(String docId, DateTime day, List<dynamic> users) {
    final shifts = <Shift>[];
    for (final u in users) {
      final uid = u?.toString() ?? '';
      if (uid.isEmpty) continue;
      shifts.add(Shift(
        id: '$docId-$uid',
        date: day,
        userId: uid,
        startUtc: null,
        endUtc: null,
      ));
    }
    return shifts;
  }

  DateTime _parseTimeToUtc(DateTime date, String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TableCalendar<String>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              selectedDayPredicate: (day) => _selectedDay != null && 
                _selectedDay!.year == day.year &&
                _selectedDay!.month == day.month &&
                _selectedDay!.day == day.day,
              onDaySelected: _onDaySelected,
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
                _loadMonthAssignedDays(focusedDay);
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focused) {
                  final dayId = _dayId(day);
                  final count = _dayShiftCounts[dayId] ?? 0;
                  if (count <= 0) return null; // usa estilo por defecto si no hay turnos
                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade200,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                selectedBuilder: (context, day, focused) {
                  final dayId = _dayId(day);
                  final count = _dayShiftCounts[dayId] ?? 0;
                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.deepPurple, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          // El detalle ahora se muestra en un modal 3/4; no se renderiza inline.
        ],
      ),
    );
  }

  // Detalle inline removido; ahora usamos modal 3/4.
  
}

// Modal 3/4 para ver guardias del día y del mes en la vista "Ver Asignaciones"
class _AdminDayShiftsSheet extends StatefulWidget {
  final DateTime day;
  const _AdminDayShiftsSheet({required this.day});

  @override
  State<_AdminDayShiftsSheet> createState() => _AdminDayShiftsSheetState();
}

class _AdminDayShiftsSheetState extends State<_AdminDayShiftsSheet> {
  bool _loading = true;
  String? _error;
  List<Shift> _dayShifts = const [];
  List<Shift> _monthShifts = const [];

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final d = widget.day;
    final dayId = _dayId(DateTime(d.year, d.month, d.day));
    final startDay = DateTime(d.year, d.month, d.day, 0, 0, 0);
    final endDay = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
    final startMonth = DateTime(d.year, d.month, 1);
    final endMonth = DateTime(d.year, d.month + 1, 0);
    try {
      final dayRes = await _fetchDayShifts(dayId, startDay, endDay);
      final monthRes = await _fetchMonthShifts(startMonth, endMonth);
      if (!mounted) return;
      setState(() {
        _dayShifts = dayRes;
        _monthShifts = monthRes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _dayId(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<List<Shift>> _fetchDayShifts(String dayId, DateTime start, DateTime end) async {
    final ref = FirebaseFirestore.instance.collection('shifts');
    // 1) Por ID directo
    final byId = await ref.doc(dayId).get();
    if (byId.exists) {
      final data = byId.data()!;
      return _extractFromDoc(byId.id, DateTime(start.year, start.month, start.day), data);
    }
    // 2) Fallback por rango de fecha
    final q = await ref
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .limit(1)
        .get();
    if (q.docs.isEmpty) return const [];
  final doc = q.docs.first;
  final data = doc.data();
  return _extractFromDoc(doc.id, DateTime(start.year, start.month, start.day), data);
  }

  Future<List<Shift>> _fetchMonthShifts(DateTime start, DateTime end) async {
    final ref = FirebaseFirestore.instance.collection('shifts');
    final q = await ref
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    final result = <Shift>[];
    for (final doc in q.docs) {
      final data = doc.data();
      // Derivar fecha del id o de timestamp
      final dateFromId = _tryParseDocIdAsDate(doc.id) ?? _tsToDate(data['date']);
      if (dateFromId == null) continue;
      result.addAll(_extractFromDoc(doc.id, DateTime(dateFromId.year, dateFromId.month, dateFromId.day), data));
    }
    return result;
  }

  DateTime? _tryParseDocIdAsDate(String id) {
    try {
      final p = id.split('-');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  List<Shift> _extractFromDoc(String docId, DateTime day, Map<String, dynamic> data) {
    final shifts = <Shift>[];
    final slots = data['slots'];
    if (slots is Map<String, dynamic>) {
      slots.forEach((uid, value) {
        if (value is List) {
          for (final slot in value) {
            if (slot is Map<String, dynamic>) {
              shifts.add(_shiftFromSlot(docId, day, uid.toString(), slot));
            }
          }
        } else if (value is Map<String, dynamic>) {
          shifts.add(_shiftFromSlot(docId, day, uid.toString(), value));
        } else {
          shifts.add(Shift(id: '$docId-$uid', date: day, userId: uid.toString()));
        }
      });
    }
    // Fallback: sin slots, usar lista de usuarios
    final users = data['users'];
    if (users is List && users.isNotEmpty) {
      for (final u in users) {
        final uid = u?.toString() ?? '';
        if (uid.isEmpty) continue;
        shifts.add(Shift(id: '$docId-$uid', date: day, userId: uid));
      }
    }
    return shifts;
  }

  Shift _shiftFromSlot(String docId, DateTime day, String uid, Map<String, dynamic> slot) {
    final start = slot['start'];
    final end = slot['end'];
    DateTime? startDt;
    DateTime? endDt;
    if (start is String) startDt = _parseTime(day, start);
    if (end is String) endDt = _parseTime(day, end);
    if (start is Timestamp) startDt = start.toDate();
    if (end is Timestamp) endDt = end.toDate();
    return Shift(id: '$docId-$uid', date: day, userId: uid, startUtc: startDt, endUtc: endDt);
  }

  DateTime _parseTime(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }


  Future<String> _resolveUserLabel(String uid) async {
    // Intentar cache local primero
    try {
      final cached = HiveCacheService().getUserLabel(uid);
      if (cached != null) return cached.toUpperCase();
    } catch (_) {}
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        final label = name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);
        // Guardar en cache
        try { await HiveCacheService().saveUserLabel(uid, label); } catch (_) {}
        return label.toUpperCase();
      }
    } catch (_) {}
    return uid;
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
                TextButton.icon(
                  onPressed: () {
                    // Cerrar modal y abrir "Asignar Guardias" con el día actual
                    Navigator.of(context).pop();
                    final cb = adminEditDayRequest;
                    if (cb != null) cb(widget.day);
                  },
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Editar este día'),
                ),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guardia del día', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_dayShifts.isEmpty)
                          Text('No hay guardias asignadas para este día.', style: TextStyle(color: cs.outline))
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _dayShifts.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final s = _dayShifts[i];
                              return ListTile(
                                leading: const Icon(Icons.person),
                                title: FutureBuilder<String>(
                                  future: _resolveUserLabel(s.userId),
                                  builder: (context, snap) => Text(snap.data ?? s.userId, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                subtitle: Text(s.startUtc != null && s.endUtc != null ? '${_fmtTime(s.startUtc!)} - ${_fmtTime(s.endUtc!)}' : 'Sin horario específico'),
                                dense: true,
                                trailing: Icon(Icons.schedule, color: cs.primary),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Text('Guardias del mes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_monthShifts.isEmpty)
                  Text('No hay guardias asignadas este mes.', style: TextStyle(color: cs.outline))
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _monthShifts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = _monthShifts[i];
                      final y = s.date.year.toString().padLeft(4, '0');
                      final m = s.date.month.toString().padLeft(2, '0');
                      final d = s.date.day.toString().padLeft(2, '0');
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: FutureBuilder<String>(
                          future: _resolveUserLabel(s.userId),
                          builder: (context, snap) => Text(snap.data ?? s.userId, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        subtitle: Text('$y-$m-$d • ${s.startUtc != null && s.endUtc != null ? '${_fmtTime(s.startUtc!)} - ${_fmtTime(s.endUtc!)}' : 'Sin horario específico'}'),
                        dense: true,
                        trailing: Icon(Icons.schedule, color: cs.primary),
                      );
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

extension on _AssignmentsViewState {
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
          child: _AdminDayShiftsSheet(day: day),
        );
      },
    );
  }
}