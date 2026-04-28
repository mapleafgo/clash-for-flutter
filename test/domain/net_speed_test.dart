import 'package:singcast/domain/net_speed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrafficSnapshot', () {
    test('defaults to zero', () {
      final speed = TrafficSnapshot();
      expect(speed.up, 0);
      expect(speed.down, 0);
      expect(speed.upTotal, 0);
      expect(speed.downTotal, 0);
    });

    test('creates with values', () {
      final speed = TrafficSnapshot(up: 1024, down: 2048);
      expect(speed.up, 1024);
      expect(speed.down, 2048);
    });

    test('JSON roundtrip with values', () {
      final speed = TrafficSnapshot(
        up: 500, down: 1500, upTotal: 5000, downTotal: 15000,
        memory: 1024, goroutines: 8, connsIn: 3, connsOut: 2,
      );
      final json = speed.toJson();
      final restored = TrafficSnapshot.fromJson(json);

      expect(restored.up, 500);
      expect(restored.down, 1500);
      expect(restored.upTotal, 5000);
      expect(restored.downTotal, 15000);
      expect(restored.memory, 1024);
      expect(restored.goroutines, 8);
      expect(restored.connsIn, 3);
      expect(restored.connsOut, 2);
    });

    test('JSON roundtrip with defaults', () {
      final speed = TrafficSnapshot();
      final json = speed.toJson();
      final restored = TrafficSnapshot.fromJson(json);

      expect(restored.up, 0);
      expect(restored.down, 0);
    });

    test('fromJson handles missing fields with defaults', () {
      final restored = TrafficSnapshot.fromJson({});
      expect(restored.up, 0);
      expect(restored.down, 0);
    });

    test('fromJson parses cff-core snake_case JSON', () {
      final json = {
        'up': 9999,
        'down': 8888,
        'up_total': 100000,
        'down_total': 200000,
        'memory': 2048,
        'goroutines': 16,
        'connections_in': 5,
        'connections_out': 4,
      };
      final speed = TrafficSnapshot.fromJson(json);
      expect(speed.up, 9999);
      expect(speed.down, 8888);
      expect(speed.upTotal, 100000);
      expect(speed.downTotal, 200000);
      expect(speed.memory, 2048);
      expect(speed.goroutines, 16);
      expect(speed.connsIn, 5);
      expect(speed.connsOut, 4);
    });

    test('toJson outputs snake_case keys', () {
      final speed = TrafficSnapshot(upTotal: 100, downTotal: 200);
      final json = speed.toJson();
      expect(json.containsKey('up_total'), true);
      expect(json.containsKey('down_total'), true);
      expect(json.containsKey('connections_in'), true);
      expect(json.containsKey('connections_out'), true);
    });

    test('NetSpeed is alias for TrafficSnapshot', () {
      final speed = NetSpeed(up: 100, down: 200);
      expect(speed.up, 100);
      expect(speed.down, 200);
    });
  });
}
