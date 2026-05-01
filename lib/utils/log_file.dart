import 'dart:io';

import 'package:singcast/domain/log.dart';

class LogFileWriter {
  static LogFileWriter? _instance;

  IOSink? _sink;
  final String _path;
  static const _maxSize = 5 * 1024 * 1024;

  LogFileWriter._(this._path);

  static LogFileWriter? get instance => _instance;

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

  void writeAll(List<LogEntry> entries) {
    final sink = _sink;
    if (sink == null) return;
    for (final e in entries) {
      sink.writeln(_formatEntry(e));
    }
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
    final p = (n, w) => n.toString().padLeft(w, '0');
    return '${p(ts.month, 2)}-${p(ts.day, 2)} '
        '${p(ts.hour, 2)}:${p(ts.minute, 2)}:${p(ts.second, 2)}.${p(ts.millisecond, 3)} '
        '[${e.type.name.toUpperCase()}] ${e.payload}';
  }
}
