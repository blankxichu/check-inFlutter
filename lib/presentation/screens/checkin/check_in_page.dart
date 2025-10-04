import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/check_in_view_model.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';
import 'package:guardias_escolares/presentation/widgets/primary_button.dart';
import 'package:guardias_escolares/presentation/screens/checkin/check_in_export_page.dart';

class CheckInPage extends ConsumerWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkInViewModelProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in en la escuela'),
        actions: [
          IconButton(
            tooltip: 'Exportar / Compartir',
            icon: const Icon(Icons.ios_share),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CheckInExportPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Icon(Icons.location_on_rounded, color: cs.primary, size: 56),
                const SizedBox(height: 8),
                Text('Ubícate en la escuela y pulsa el botón para registrar asistencia.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                if (state.mensaje != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(state.mensaje!)),
                        ],
                      ),
                    ),
                  ),
                if (state.error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: cs.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(state.error!)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: 'Check-in',
                        icon: Icons.login, // entrada
                        loading: state.procesando,
                        onPressed: state.procesando ? null : () => ref.read(checkInViewModelProvider.notifier).hacerCheckIn(ref),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Check-out',
                        icon: Icons.logout, // salida
                        loading: state.procesando,
                        onPressed: state.procesando ? null : () => ref.read(checkInViewModelProvider.notifier).hacerCheckOut(ref),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Mis check-ins recientes', style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 8),
                // Make the list area flexible to avoid overflow on short screens
                Expanded(child: _UserCheckInsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

  class _UserCheckInsList extends ConsumerStatefulWidget {
    @override
    ConsumerState<_UserCheckInsList> createState() => _UserCheckInsListState();
  }

  class _UserCheckInsListState extends ConsumerState<_UserCheckInsList> {
    int _limit = 10;

    @override
    Widget build(BuildContext context) {
      final auth = ref.watch(auth_vm.authViewModelProvider);
      return auth.maybeWhen(
        authenticated: (user) {
          final repo = ref.watch(checkInRepositoryProvider);
          final to = DateTime.now().toUtc();
          final from = to.subtract(const Duration(days: 30));
          final stream = repo.watchUserCheckIns(userId: user.uid, fromUtc: from, toUtc: to, limit: _limit);
          return StreamBuilder<List<CheckIn>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              final data = snapshot.data ?? const [];
              if (data.isEmpty) {
                return const Center(child: Text('No hay check-ins registrados en los últimos 30 días'));
              }
              // Fill available space and let the list scroll
              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: _buildDailyPairs(data).length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final pair = _buildDailyPairs(data)[i];
                        final cs = Theme.of(context).colorScheme;
                        return ListTile(
                          title: Text(pair['date'] as String),
                          subtitle: Row(
                            children: [
                              if (pair['in'] != null) ...[
                                Icon(Icons.arrow_circle_right, color: Colors.green, size: 18),
                                const SizedBox(width: 4),
                                Text(pair['in'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                              if (pair['out'] != null) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.arrow_circle_left, color: Colors.green, size: 18),
                                const SizedBox(width: 4),
                                Text(pair['out'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                          trailing: Text(pair['duration'] ?? '', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          dense: true,
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _limit += 20;
                        });
                      },
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Ver más (+20)'),
                    ),
                  ),
                ],
              );
            },
          );
        },
        orElse: () => const SizedBox.shrink(),
      );
    }
  }

  List<Map<String, String?>> _buildDailyPairs(List<CheckIn> raw) {
    // Construir sesiones (in->out) múltiples por día. Un nuevo check-in tras un check-out inicia sesión nueva.
    final byDay = <String, List<CheckIn>>{};
    for (final c in raw) {
      final local = c.timestampUtc.toLocal();
      final dayId = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(dayId, () => []).add(c);
    }
    final sessions = <Map<String, String?>>[];
    final sortedDays = byDay.keys.toList()..sort((a,b)=>b.compareTo(a));
    String fmt(DateTime d)=>'${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    for (final day in sortedDays) {
      final events = byDay[day]!..sort((a,b)=>a.timestampUtc.compareTo(b.timestampUtc));
      DateTime? openIn;
      for (final ev in events) {
        if (ev.type == CheckInType.inEvent) {
          // Si había una sesión abierta sin out, la cerramos incompleta
          if (openIn != null) {
            sessions.add({'date': day, 'in': fmt(openIn), 'out': null, 'duration': null});
          }
          openIn = ev.timestampUtc.toLocal();
        } else { // outEvent
          if (openIn != null) {
            final outTs = ev.timestampUtc.toLocal();
            Duration diff = Duration.zero;
            String? dur;
              if (outTs.isAfter(openIn)) {
                diff = outTs.difference(openIn);
                final h = diff.inHours; final m = diff.inMinutes % 60;
                dur = '${h}h ${m}m';
              }
            sessions.add({'date': day, 'in': fmt(openIn), 'out': fmt(outTs), 'duration': dur});
            openIn = null; // sesión cerrada
          } else {
            // out sin in previo: registrar sesión huérfana
            final outTs = ev.timestampUtc.toLocal();
            sessions.add({'date': day, 'in': null, 'out': fmt(outTs), 'duration': null});
          }
        }
      }
      if (openIn != null) {
        // Sesión abierta sin out
        sessions.add({'date': day, 'in': fmt(openIn), 'out': null, 'duration': null});
        openIn = null;
      }
    }
    // Ya están ordenadas por día desc y dentro del día por orden cronológico; opcional invertir por sesión recent-first:
    return sessions;
  }
