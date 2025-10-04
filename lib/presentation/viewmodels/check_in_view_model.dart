import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:guardias_escolares/data/checkin/firestore_check_in_repository.dart';
import 'package:guardias_escolares/domain/checkin/repositories/check_in_repository.dart';
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';
import 'package:guardias_escolares/domain/checkin/usecases/do_check_in.dart';
import 'package:guardias_escolares/domain/checkin/usecases/do_check_out.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;
import 'package:guardias_escolares/core/config/app_config.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  // Simple: si hay Firebase, usar Firestore; si no, lanzar error al usar.
  if (Firebase.apps.isNotEmpty) {
    return FirestoreCheckInRepository(db: FirebaseFirestore.instance);
  }
  throw StateError('Firebase no está inicializado');
});

final geofenceRepositoryProvider = Provider<GeofenceRepository>((ref) {
  if (Firebase.apps.isNotEmpty) {
    // TODO: obtener schoolId real desde el contexto de usuario/escuela
    return FirestoreGeofenceRepository(schoolId: AppConfig.defaultSchoolId, db: FirebaseFirestore.instance);
  }
  // Fallback local: geofence en 0,0 con 100m (solo para desarrollo sin Firebase)
  return _LocalGeofenceRepository();
});

final doCheckInProvider = Provider<DoCheckIn>((ref) {
  return DoCheckIn(
    checkIns: ref.watch(checkInRepositoryProvider),
    geofence: ref.watch(geofenceRepositoryProvider),
  );
});

final doCheckOutProvider = Provider<DoCheckOut>((ref) {
  return DoCheckOut(
    checkIns: ref.watch(checkInRepositoryProvider),
    geofence: ref.watch(geofenceRepositoryProvider),
  );
});

class CheckInState {
  final bool procesando;
  final String? mensaje;
  final String? error;
  const CheckInState({this.procesando = false, this.mensaje, this.error});

  CheckInState copyWith({bool? procesando, String? mensaje, String? error}) =>
      CheckInState(procesando: procesando ?? this.procesando, mensaje: mensaje, error: error);
}

class CheckInViewModel extends Notifier<CheckInState> {
  @override
  CheckInState build() => const CheckInState();

  Future<void> solicitarPermisos() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Permisos de ubicación denegados permanentemente');
    }
  }

  Future<void> hacerCheckIn(WidgetRef ref) async {
    state = state.copyWith(procesando: true, mensaje: null, error: null);
    try {
      await solicitarPermisos();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final user = ref.read(auth_vm.authViewModelProvider).maybeWhen(
            authenticated: (u) => u,
            orElse: () => null,
          );
      if (user == null) throw StateError('Debe iniciar sesión');
      // Validación: no permitir un nuevo check-in si el último evento es un IN sin OUT posterior
      final repo = ref.read(checkInRepositoryProvider);
      final last = await repo.getLastCheckIn(user.uid);
      if (last != null && last.type == CheckInType.inEvent) {
        throw StateError('Ya tienes un check-in abierto. Primero realiza el check-out.');
      }
      await ref.read(doCheckInProvider).call(
            userId: user.uid,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
      state = state.copyWith(procesando: false, mensaje: 'Check-in registrado');
    } catch (e) {
      state = state.copyWith(procesando: false, error: e.toString());
    }
  }

  Future<void> hacerCheckOut(WidgetRef ref) async {
    state = state.copyWith(procesando: true, mensaje: null, error: null);
    try {
      await solicitarPermisos();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final user = ref.read(auth_vm.authViewModelProvider).maybeWhen(
            authenticated: (u) => u,
            orElse: () => null,
          );
      if (user == null) throw StateError('Debe iniciar sesión');
      // Validación adicional: evitar check-out consecutivo si último ya es OUT
      final repo = ref.read(checkInRepositoryProvider);
      final last = await repo.getLastCheckIn(user.uid);
      if (last == null) {
        throw StateError('No tienes un check-in abierto para cerrar.');
      }
      if (last.type == CheckInType.outEvent) {
        throw StateError('El último evento ya es un check-out. Realiza un nuevo check-in primero.');
      }
      await ref.read(doCheckOutProvider).call(
            userId: user.uid,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
      state = state.copyWith(procesando: false, mensaje: 'Check-out registrado');
    } catch (e) {
      state = state.copyWith(procesando: false, error: e.toString());
    }
  }
}

final checkInViewModelProvider = NotifierProvider<CheckInViewModel, CheckInState>(() => CheckInViewModel());

class _LocalGeofenceRepository implements GeofenceRepository {
  @override
  Future<GeofenceConfig> getGeofence() async => const GeofenceConfig(
        latitude: AppConfig.defaultSchoolLat,
        longitude: AppConfig.defaultSchoolLon,
        radiusMeters: AppConfig.defaultGeofenceRadiusM,
      );
}
