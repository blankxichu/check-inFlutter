import 'package:flutter_test/flutter_test.dart';
import 'package:guardias_escolares/presentation/screens/admin/admin_shifts_manager_page.dart';

void main() {
  group('sanitizeIntervalsForTesting', () {
    test('returns sanitized copy when ranges are valid and ordered', () {
      final ranges = <ShiftInterval>[
        const ShiftInterval(start: '08:00', end: '09:00'),
        const ShiftInterval(start: '10:00', end: '11:00'),
      ];

      final sanitized = sanitizeIntervalsForTesting(ranges);

      expect(sanitized, isNotNull);
      expect(sanitized, isNot(same(ranges)));
      expect(sanitized!.length, ranges.length);
      for (var i = 0; i < ranges.length; i++) {
        expect(sanitized[i].start, ranges[i].start);
        expect(sanitized[i].end, ranges[i].end);
      }
    });

    test('returns null when any interval has start greater than or equal to end', () {
      final ranges = <ShiftInterval>[
        const ShiftInterval(start: '08:00', end: '07:00'),
      ];

      final sanitized = sanitizeIntervalsForTesting(ranges);

      expect(sanitized, isNull);
    });

    test('returns null when intervals overlap', () {
      final ranges = <ShiftInterval>[
        const ShiftInterval(start: '08:00', end: '10:00'),
        const ShiftInterval(start: '09:30', end: '11:00'),
      ];

      final sanitized = sanitizeIntervalsForTesting(ranges);

      expect(sanitized, isNull);
    });

    test('filters out empty intervals and keeps valid ones', () {
      final ranges = <ShiftInterval>[
        const ShiftInterval(start: '08:00', end: '09:00'),
        const ShiftInterval(start: '', end: ''),
      ];

      final sanitized = sanitizeIntervalsForTesting(ranges);

      expect(sanitized, isNotNull);
      expect(sanitized!.length, 1);
      expect(sanitized.first.start, '08:00');
      expect(sanitized.first.end, '09:00');
    });
  });

  group('hhmmToMinutesForTesting', () {
    test('parses valid HH:mm value', () {
      expect(hhmmToMinutesForTesting('08:30'), 510);
      expect(hhmmToMinutesForTesting('00:00'), 0);
      expect(hhmmToMinutesForTesting('23:59'), 1439);
    });

    test('returns null for invalid input', () {
      expect(hhmmToMinutesForTesting(''), isNull);
      expect(hhmmToMinutesForTesting('invalid'), isNull);
      expect(hhmmToMinutesForTesting('08'), isNull);
    });
  });
}
