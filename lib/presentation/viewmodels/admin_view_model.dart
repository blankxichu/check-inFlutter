import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/domain/admin/entities/admin_metrics.dart';
import 'package:guardias_escolares/domain/admin/repositories/admin_repository.dart';
import 'package:guardias_escolares/domain/admin/usecases/get_admin_metrics.dart';
import 'package:guardias_escolares/domain/admin/usecases/set_user_role.dart';
import 'package:guardias_escolares/data/admin/firebase_admin_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminState {
  final AdminMetrics? metrics;
  final bool loading;
  final String? error;
  const AdminState({this.metrics, this.loading = false, this.error});

  AdminState copyWith({AdminMetrics? metrics, bool? loading, String? error}) =>
      AdminState(metrics: metrics ?? this.metrics, loading: loading ?? this.loading, error: error);
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) => FirebaseAdminRepository());
final getAdminMetricsProvider = Provider<GetAdminMetrics>((ref) => GetAdminMetrics(ref.watch(adminRepositoryProvider)));
final setUserRoleProvider = Provider<SetUserRole>((ref) => SetUserRole(ref.watch(adminRepositoryProvider)));

class AdminViewModel extends Notifier<AdminState> {
  late final GetAdminMetrics _getMetrics;
  late final SetUserRole _setRole;

  @override
  AdminState build() {
    _getMetrics = ref.read(getAdminMetricsProvider);
    _setRole = ref.read(setUserRoleProvider);
    return const AdminState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final metrics = await _getMetrics(DateTime.now().toUtc());
      state = state.copyWith(loading: false, metrics: metrics);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> setRole(String uid, String role) async {
    try {
      await _setRole(uid: uid, role: role);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> setRoleByEmail(String email, String role) async {
    try {
      // Llamar directamente a la Cloud Function con email
      final f = FirebaseFunctions.instanceFor(region: 'us-central1');
      await f.httpsCallable('setUserRole').call({
        'email': email,
        'role': role,
      });
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final adminViewModelProvider = NotifierProvider<AdminViewModel, AdminState>(() => AdminViewModel());
