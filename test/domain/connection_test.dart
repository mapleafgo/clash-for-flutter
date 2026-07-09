import 'package:singcast/domain/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionEvent', () {
    test('fromJson parses singcast-cli JSON', () {
      final json = {'event_type': 0, 'id': 'conn-123'};
      final event = ConnectionEvent.fromJson(json);
      expect(event.eventType, 0);
      expect(event.id, 'conn-123');
    });

    test('fromJson handles missing fields', () {
      final event = ConnectionEvent.fromJson({});
      expect(event.eventType, 0);
      expect(event.id, '');
    });

  });

  group('ConnectionEventsPayload', () {
    test('fromJson parses reset with items', () {
      final json = {
        'reset': true,
        'items': [
          {'event_type': 0, 'id': 'conn-1'},
          {'event_type': 0, 'id': 'conn-2'},
        ],
      };
      final payload = ConnectionEventsPayload.fromJson(json);
      expect(payload.reset, true);
      expect(payload.items.length, 2);
      expect(payload.items[0].eventType, 0);
      expect(payload.items[0].id, 'conn-1');
    });

    test('fromJson handles empty items', () {
      final json = {'reset': false, 'items': []};
      final payload = ConnectionEventsPayload.fromJson(json);
      expect(payload.reset, false);
      expect(payload.items, isEmpty);
    });

    test('fromJson handles missing fields', () {
      final payload = ConnectionEventsPayload.fromJson({});
      expect(payload.reset, false);
      expect(payload.items, isEmpty);
    });

    test('fromJson handles null items', () {
      final payload = ConnectionEventsPayload.fromJson({'reset': true});
      expect(payload.items, isEmpty);
    });
  });
}
