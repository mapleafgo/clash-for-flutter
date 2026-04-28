import 'package:singcast/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('formats 0 bytes', () {
      expect(formatBytes(0), '0.0 B');
    });

    test('formats single byte', () {
      expect(formatBytes(1), '1.0 B');
    });

    test('formats bytes under 1 KB', () {
      expect(formatBytes(512), '512.0 B');
    });

    test('formats 1024 bytes as B (boundary is > 1024)', () {
      expect(formatBytes(1024), '1024.0 B');
    });

    test('formats above 1024 as KB', () {
      expect(formatBytes(1025), '1.0 KB');
    });

    test('formats KB range', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('formats MB boundary', () {
      expect(formatBytes(1048576), '1024.0 KB');
      expect(formatBytes(1048577), '1.0 MB');
    });

    test('formats GB boundary', () {
      expect(formatBytes(1073741824), '1024.0 MB');
      expect(formatBytes(1073741825), '1.0 GB');
    });

    test('formats TB boundary', () {
      expect(formatBytes(1099511627776), '1024.0 GB');
      expect(formatBytes(1099511627777), '1.0 TB');
    });

    test('formats PB boundary', () {
      expect(formatBytes(1125899906842624), '1024.0 TB');
      expect(formatBytes(1125899906842625), '1.0 PB');
    });

    test('formats large value without exceeding PB', () {
      final result = formatBytes(5629499534213120);
      expect(result, contains('PB'));
    });

    test('formats typical network speed values', () {
      expect(formatBytes(102400), contains('KB'));
      expect(formatBytes(10485760), contains('MB'));
    });
  });
}
