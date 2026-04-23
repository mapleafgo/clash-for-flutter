import 'dart:async';
import 'dart:convert';

import 'package:clash_for_flutter/domain/connection.dart';
import 'package:clash_for_flutter/domain/log.dart';
import 'package:clash_for_flutter/domain/net_speed.dart';
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

String _ws(String path) => 'ws://${Constants.rustAddr}$path';

Stream<NetSpeed> trafficStream() {
  final channel = WebSocketChannel.connect(Uri.parse(_ws('/traffic')));
  return channel.stream.map((e) => NetSpeed.fromJson(jsonDecode(e)));
}

Stream<LogEntry> logsStream(LogLevel level) {
  final uri = Uri.parse(_ws('/logs?level=${level.name}'));
  final channel = WebSocketChannel.connect(uri);
  return channel.stream.map((e) {
    final entry = LogEntry.fromJson(jsonDecode(e));
    return entry;
  });
}

Stream<ConnectionsSnapshot> connectionsStream() {
  final channel = WebSocketChannel.connect(Uri.parse(_ws('/connections')));
  return channel.stream.map((e) =>
      ConnectionsSnapshot.fromJson(jsonDecode(e)));
}