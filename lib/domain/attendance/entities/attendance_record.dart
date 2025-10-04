class AttendanceRecord {
  final String id;
  final String userId;
  final String tipo; // 'entrada' | 'salida'
  final DateTime timestampUtc;
  final String? fotoUrl;
  final double? latitude;
  final double? longitude;

  const AttendanceRecord({
    required this.id,
    required this.userId,
    required this.tipo,
    required this.timestampUtc,
    this.fotoUrl,
    this.latitude,
    this.longitude,
  });
}
