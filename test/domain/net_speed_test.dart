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
      final stats = CoreStats(up: 1024, down: 2048, upTotal: 5000, downTotal: 15000);
      expect(stats.up, 1024);
      expect(stats.down, 2048);
      expect(stats.upTotal, 5000);
      expect(stats.downTotal, 15000);
    });

    test('JSON roundtrip with values', () {
      final stats = CoreStats(
        up: 500, down: 1500, upTotal: 5000, downTotal: 15000,
        memory: 1024, connections: 8, startedAt: 12345,
      );
      final json = stats.toJson();
      final restored = CoreStats.fromKernelJson(json);

      expect(restored.upTotal, 500);
      expect(restored.downTotal, 1500);
      expect(restored.memory, 1024);
      expect(restored.connections, 8);
      expect(restored.startedAt, 12345);
    });

    test('JSON roundtrip with defaults', () {
      final stats = CoreStats();
      final json = stats.toJson();
      final restored = CoreStats.fromKernelJson(json);

      expect(restored.upTotal, 0);
      expect(restored.downTotal, 0);
    });

    test('fromKernelJson handles missing fields with defaults', () {
      final restored = CoreStats.fromKernelJson({});
      expect(restored.upTotal, 0);
      expect(restored.downTotal, 0);
    });

    test('fromJson parses cff-core snake_case JSON', () {
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

    test('toJson outputs snake_case keys', () {
      final stats = CoreStats(upTotal: 100, downTotal: 200, startedAt: 999);
      final json = stats.toJson();
      expect(json.containsKey('up_total'), true);
      expect(json.containsKey('down_total'), true);
      expect(json.containsKey('started_at'), true);
    });
  });
}
