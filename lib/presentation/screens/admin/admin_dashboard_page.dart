import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/screens/admin/admin_dashboard_new.dart' as newui;

// Deja la nueva interfaz como la pantalla por defecto del Admin Dashboard
class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const newui.AdminDashboardPage();
  }
}