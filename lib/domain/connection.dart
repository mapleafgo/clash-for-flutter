/// singcast-cli returns: {"event_type": int32, "id": string}
class ConnectionEvent {
  final int eventType;
  final String id;

  ConnectionEvent({required this.eventType, required this.id});

  factory ConnectionEvent.fromJson(Map<String, dynamic> json) => ConnectionEvent(
    eventType: (json['event_type'] as num?)?.toInt() ?? 0,
    id: json['id'] as String? ?? '',
  );
}

/// singcast-cli connection events payload:
/// {"reset": bool, "items": [ConnectionEvent, ...]}
class ConnectionEventsPayload {
  final bool reset;
  final List<ConnectionEvent> items;

  ConnectionEventsPayload({this.reset = false, this.items = const []});

  factory ConnectionEventsPayload.fromJson(Map<String, dynamic> json) =>
      ConnectionEventsPayload(
        reset: json['reset'] as bool? ?? false,
        items: (json['items'] as List?)
            ?.map((e) => ConnectionEvent.fromJson(e as Map<String, dynamic>))
            .toList() ?? [],
      );
}
