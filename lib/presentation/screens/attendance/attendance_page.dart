import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/attendance_view_model.dart';

class AttendancePage extends ConsumerWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(attendanceViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Asistencia')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.mensaje != null)
                  Text(state.mensaje!, style: const TextStyle(color: Colors.green)),
                if (state.error != null)
                  Text(state.error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                if (state.fotoLocalPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(state.fotoLocalPath!), height: 160, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: state.procesando
                            ? null
                            : () => ref.read(attendanceViewModelProvider.notifier).tomarFoto(),
                        child: const Text('Adjuntar foto'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: state.procesando
                            ? null
                            : () => ref.read(attendanceViewModelProvider.notifier).registrarEntrada(ref),
                        child: state.procesando
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Registrar entrada'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.procesando
                            ? null
                            : () => ref.read(attendanceViewModelProvider.notifier).registrarSalida(ref),
                        child: state.procesando
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Registrar salida'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
