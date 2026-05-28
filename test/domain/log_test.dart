import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogEntry', () {
    test('fromJson parses singcast-cli JSON', () {
      final json = {'level': 4, 'message': 'test log message'};
      final entry = LogEntry.fromJson(json);
      expect(entry.type, LogLevel.info);
      expect(entry.payload, 'test log message');
    });

    test('fromJson handles missing fields', () {
      final entry = LogEntry.fromJson({});
      expect(entry.type, LogLevel.info);
      expect(entry.payload, '');
    });

    test('fromJson maps level correctly', () {
      // sing-box levels: 0=Panic,1=Fatal,2=Error → error, 3→warning, 4→info, 5,6→debug
      expect(LogEntry.fromJson({'level': 0, 'message': ''}).type, LogLevel.error);
      expect(LogEntry.fromJson({'level': 1, 'message': ''}).type, LogLevel.error);
      expect(LogEntry.fromJson({'level': 2, 'message': ''}).type, LogLevel.error);
      expect(LogEntry.fromJson({'level': 3, 'message': ''}).type, LogLevel.warning);
      expect(LogEntry.fromJson({'level': 4, 'message': ''}).type, LogLevel.info);
      expect(LogEntry.fromJson({'level': 5, 'message': ''}).type, LogLevel.debug);
      expect(LogEntry.fromJson({'level': 6, 'message': ''}).type, LogLevel.debug);
    });

    test('toJson outputs lowercase keys', () {
      final entry = LogEntry(type: LogLevel.warning, payload: 'hello', timestamp: DateTime(2026));
      final json = entry.toJson();
      expect(json['level'], 3);
      expect(json['message'], 'hello');
    });

    test('JSON roundtrip', () {
      final entry = LogEntry(type: LogLevel.error, payload: 'error occurred', timestamp: DateTime(2026));
      final restored = LogEntry.fromJson(entry.toJson());
      expect(restored.type, LogLevel.error);
      expect(restored.payload, 'error occurred');
    });
  });
}
