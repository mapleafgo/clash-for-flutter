import 'dart:developer' as developer;
import 'dart:io';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/log.dart';

class LogFileWriter {
  static LogFileWriter? _instance;

  final String _path;
  IOSink? _sink;
  static const _maxSize = 5 * 1024 * 1024;

  LogLevel _minLevel = LogLevel.info;

  LogFileWriter._(this._path);

  static LogFileWriter? get instance => _instance;
  static String? get logFilePath => _instance?._path;

  static Future<void> init(String path) async {
    final writer = LogFileWriter._(path);
    final file = File(path);
    try {
      if (await file.exists() && await file.length() > _maxSize) {
        await file.writeAsString('');
      }
    } catch (_) {}
    writer._sink = file.openWrite(mode: FileMode.append);
    _instance = writer;
  }

  void setMinLevel(LogLevel level) => _minLevel = level;

  bool _shouldLog(LogLevel level) => level.index >= _minLevel.index;

  void writeAll(List<LogEntry> entries) {
    final sink = _sink;
    if (sink == null) return;
    try {
      for (final e in entries) {
        if (_shouldLog(e.type)) sink.writeln(_formatEntry(e));
      }
    } catch (_) {}
  }

  void log(String message, {LogLevel level = LogLevel.info, String? name}) {
    final sink = _sink;
    if (sink == null || !_shouldLog(level)) return;
    final entry = LogEntry(
      type: level,
      payload: name != null ? '[$name] $message' : message,
      timestamp: DateTime.now(),
    );
    try {
      sink.writeln(_formatEntry(entry));
    } catch (_) {}
    developer.log(message, name: name ?? 'app');
  }

  Future<void> flush() async {
    await _sink?.flush();
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _instance = null;
  }

  String _formatEntry(LogEntry e) {
    final ts = e.timestamp;
    String p(n, w) => n.toString().padLeft(w, '0');
    return '${p(ts.month, 2)}-${p(ts.day, 2)} '
        '${p(ts.hour, 2)}:${p(ts.minute, 2)}:${p(ts.second, 2)}.${p(ts.millisecond, 3)} '
        '[${e.type.name.toUpperCase()}] ${e.payload}';
  }
}
