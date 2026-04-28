import 'package:singcast/domain/connection.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibCore handleConnectionEvents', () {
    late LibCore core;

    setUp(() {
      core = LibCore.instance;
    });

    test('adds connections on event_type=0', () {
      core.handleConnectionEvents(ConnectionEventsPayload(
        reset: true,
        items: [
          ConnectionEvent(eventType: 0, id: 'a'),
          ConnectionEvent(eventType: 0, id: 'b'),
        ],
      ));
      expect(core.activeConnectionsSignal.value, 2);
    });

    test('removes connections on event_type>0', () {
      core.handleConnectionEvents(ConnectionEventsPayload(
        reset: true,
        items: [
          ConnectionEvent(eventType: 0, id: 'a'),
          ConnectionEvent(eventType: 0, id: 'b'),
        ],
      ));
      core.handleConnectionEvents(ConnectionEventsPayload(
        items: [ConnectionEvent(eventType: 1, id: 'a')],
      ));
      expect(core.activeConnectionsSignal.value, 1);
    });

    test('reset clears all then re-adds', () {
      core.handleConnectionEvents(ConnectionEventsPayload(
        reset: true,
        items: [ConnectionEvent(eventType: 0, id: 'x')],
      ));
      expect(core.activeConnectionsSignal.value, 1);

      core.handleConnectionEvents(ConnectionEventsPayload(
        reset: true,
        items: [
          ConnectionEvent(eventType: 0, id: 'y'),
          ConnectionEvent(eventType: 0, id: 'z'),
        ],
      ));
      expect(core.activeConnectionsSignal.value, 2);
    });

    test('non-reset appends to existing', () {
      core.handleConnectionEvents(ConnectionEventsPayload(
        reset: true,
        items: [ConnectionEvent(eventType: 0, id: 'a')],
      ));
      core.handleConnectionEvents(ConnectionEventsPayload(
        items: [ConnectionEvent(eventType: 0, id: 'b')],
      ));
      expect(core.activeConnectionsSignal.value, 2);
    });

    test('empty payload with reset clears count', () {
      core.handleConnectionEvents(ConnectionEventsPayload(
        reset: true,
        items: [ConnectionEvent(eventType: 0, id: 'a')],
      ));
      core.handleConnectionEvents(ConnectionEventsPayload(reset: true));
      expect(core.activeConnectionsSignal.value, 0);
    });
  });
}
