enum CheckInType { inEvent, outEvent }

class CheckIn {
  final String id;
  final String userId;
  final DateTime timestampUtc;
  final double latitude;
  final double longitude;
  final CheckInType type; // in o out

  const CheckIn({
    required this.id,
    required this.userId,
    required this.timestampUtc,
    required this.latitude,
    required this.longitude,
    required this.type,
  });
}
