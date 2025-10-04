import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:guardias_escolares/domain/attendance/repositories/attendance_repository.dart';
import 'package:guardias_escolares/domain/attendance/usecases/register_attendance.dart';
import 'package:guardias_escolares/data/attendance/firestore_attendance_repository.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;

class AttendanceState {
  final bool procesando;
  final String? mensaje;
  final String? error;
  final String? fotoLocalPath;
  const AttendanceState({this.procesando = false, this.mensaje, this.error, this.fotoLocalPath});

  AttendanceState copyWith({bool? procesando, String? mensaje, String? error, String? fotoLocalPath}) =>
      AttendanceState(
        procesando: procesando ?? this.procesando,
        mensaje: mensaje,
        error: error,
        fotoLocalPath: fotoLocalPath ?? this.fotoLocalPath,
      );
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) => FirestoreAttendanceRepository());
final photoStorageRepositoryProvider = Provider<PhotoStorageRepository>((ref) => FirebasePhotoStorageRepository());
final registerAttendanceProvider = Provider<RegisterAttendance>((ref) => RegisterAttendance(
      repo: ref.watch(attendanceRepositoryProvider),
      storage: ref.watch(photoStorageRepositoryProvider),
    ));

class AttendanceViewModel extends Notifier<AttendanceState> {
  final _picker = ImagePicker();
  @override
  AttendanceState build() => const AttendanceState();

  Future<void> tomarFoto() async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
    if (img != null) {
      state = state.copyWith(fotoLocalPath: img.path);
    }
  }

  Future<void> registrarEntrada(WidgetRef ref) async => _registrar('entrada', ref);
  Future<void> registrarSalida(WidgetRef ref) async => _registrar('salida', ref);

  Future<void> _registrar(String tipo, WidgetRef ref) async {
    state = state.copyWith(procesando: true, mensaje: null, error: null);
    final user = ref.read(auth_vm.authViewModelProvider).maybeWhen(
          authenticated: (u) => u,
          orElse: () => null,
        );
    try {
      if (user == null) throw StateError('Debe iniciar sesión');

      final usecase = ref.read(registerAttendanceProvider);
      if (tipo == 'entrada') {
        await usecase.entrada(userId: user.uid, fotoLocalPath: state.fotoLocalPath);
      } else {
        await usecase.salida(userId: user.uid, fotoLocalPath: state.fotoLocalPath);
      }
      state = state.copyWith(procesando: false, mensaje: 'Registro de $tipo exitoso', fotoLocalPath: null);
      await _flushOfflineQueueIfAny();
    } catch (e) {
      // Guardar en cola offline y avisar
      await _enqueueOffline(tipo, user?.uid, state.fotoLocalPath);
      state = state.copyWith(procesando: false, error: 'Sin conexión. Guardado para enviar luego.');
    }
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/attendance_queue.json');
  }

  Future<void> _enqueueOffline(String tipo, String? userId, String? fotoPath) async {
    final f = await _queueFile();
    List list = [];
    if (await f.exists()) {
      list = jsonDecode(await f.readAsString());
    }
    list.add({'tipo': tipo, 'userId': userId, 'foto': fotoPath});
    await f.writeAsString(jsonEncode(list));
  }

  Future<void> _flushOfflineQueueIfAny() async {
    try {
      // Intentar vaciar cola si hay conectividad
      await FirebaseFirestore.instance.collection('_ping').doc('x').get();
      final f = await _queueFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      final list = List<Map<String, dynamic>>.from(raw);
      if (list.isEmpty) return;

      final usecase = ref.read(registerAttendanceProvider);
      final remaining = <Map<String, dynamic>>[];
      for (final item in list) {
        final tipo = item['tipo'] as String?;
        final uid = item['userId'] as String?;
        final foto = item['foto'] as String?;
        if (tipo == null || uid == null) {
          continue; // descartar entradas corruptas
        }
        try {
          if (tipo == 'entrada') {
            await usecase.entrada(userId: uid, fotoLocalPath: foto);
          } else {
            await usecase.salida(userId: uid, fotoLocalPath: foto);
          }
        } catch (_) {
          remaining.add(item); // mantener si falla
        }
      }
      await f.writeAsString(jsonEncode(remaining));
    } catch (_) {
      // Mantener cola si falla
    }
  }
}

final attendanceViewModelProvider = NotifierProvider<AttendanceViewModel, AttendanceState>(() => AttendanceViewModel());
