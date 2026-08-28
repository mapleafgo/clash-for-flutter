import 'package:singcast/domain/net_speed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoreStats', () {
    test('defaults to zero', () {
      final stats = CoreStats();
      expect(stats.up, 0);
      expect(stats.down, 0);
      expect(stats.upTotal, 0);
      expect(stats.downTotal, 0);
      expect(stats.memory, 0);
      expect(stats.connections, 0);
    });

    test('creates with values', () {
      final stats = CoreStats(
        up: 1024,
        down: 2048,
        upTotal: 5000,
        downTotal: 15000,
      );
      expect(stats.up, 1024);
      expect(stats.down, 2048);
      expect(stats.upTotal, 5000);
      expect(stats.downTotal, 15000);
    });

    test('fromKernelJson handles missing fields with defaults', () {
      final restored = CoreStats.fromKernelJson({});
      expect(restored.upTotal, 0);
      expect(restored.downTotal, 0);
    });

    test('fromJson parses singcast-cli snake_case JSON', () {
      final json = {
        'up': 9999,
        'down': 8888,
        'memory': 2048,
        'connections': 16,
        'started_at': 1234567890,
      };
      final stats = CoreStats.fromKernelJson(json);
      expect(stats.upTotal, 9999);
      expect(stats.downTotal, 8888);
      expect(stats.memory, 2048);
      expect(stats.connections, 16);
      expect(stats.startedAt, 1234567890);
    });
  });
}
