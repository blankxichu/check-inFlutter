import 'package:equatable/equatable.dart';

class Shift extends Equatable {
  final String id; // day id + user id
  final DateTime date; // only date part is relevant (UTC at 00:00)
  final String userId;
  final int capacity; // how many parents allowed per day
  final DateTime? startUtc; // inicio del turno (mismo día)
  final DateTime? endUtc;   // fin del turno (mismo día)

  const Shift({
    required this.id,
    required this.date,
    required this.userId,
    this.capacity = 1,
    this.startUtc,
    this.endUtc,
  });

  @override
  List<Object?> get props => [id, date, userId, capacity, startUtc, endUtc];
}
