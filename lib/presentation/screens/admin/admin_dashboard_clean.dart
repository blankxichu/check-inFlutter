import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/admin_view_model.dart';

class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Cargar métricas al inicializar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adminViewModelProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adminState = ref.watch(adminViewModelProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Panel'),
              Tab(icon: Icon(Icons.event_note), text: 'Asignaciones'),
            ],
          ),
          actions: [
            // Botón para acceder a la nueva interfaz
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AdminDashboardNewPage(),
                  ),
                );
              },
              icon: const Icon(Icons.new_releases),
              tooltip: 'Nueva Interfaz Simplificada',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // Tab 1: Panel de métricas básicas
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Métricas del Sistema',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              ElevatedButton(
                                onPressed: () => ref.read(adminViewModelProvider.notifier).load(),
                                child: const Text('Actualizar'),
                              ),
                              const SizedBox(width: 12),
                              if (adminState.loading) const CircularProgressIndicator(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (adminState.error != null)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                adminState.error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (adminState.metrics != null) ...[
                            _buildMetricCard('Total de Padres', '${adminState.metrics!.totalParents}', Icons.people),
                            const SizedBox(height: 8),
                            _buildMetricCard('Guardias este mes', '${adminState.metrics!.totalShiftsThisMonth}', Icons.calendar_month),
                            const SizedBox(height: 8),
                            _buildMetricCard('Check-ins hoy', '${adminState.metrics!.totalCheckInsToday}', Icons.check_circle),
                          ] else if (!adminState.loading)
                            const Text('No hay métricas disponibles'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Botón destacado para nueva interfaz
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.new_releases, size: 48, color: Colors.blue),
                          const SizedBox(height: 8),
                          const Text(
                            'Nueva Interfaz Simplificada',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Interfaz renovada para asignar guardias con flujo simplificado:\n'
                            '• Calendario visual con días ocupados\n'
                            '• Búsqueda automática de usuarios\n'
                            '• Horarios en combobox\n'
                            '• Múltiples turnos por día\n'
                            '• Confirmación antes de aplicar',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AdminDashboardNewPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.launch),
                            label: const Text('Probar Nueva Interfaz'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Tab 2: Vista básica de asignaciones
            const Center(
              child: Text(
                'Vista de asignaciones básica.\nUsa la "Nueva Interfaz Simplificada" para gestión completa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Clase para compatibilidad con la nueva interfaz
class AdminDashboardNewPage extends StatelessWidget {
  const AdminDashboardNewPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirigir a la nueva interfaz implementada en admin_dashboard_new.dart
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cargando Nueva Interfaz...'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('La nueva interfaz está en admin_dashboard_new.dart'),
            SizedBox(height: 8),
            Text('Importa y usa directamente esa clase para la funcionalidad completa.'),
          ],
        ),
      ),
    );
  }
}