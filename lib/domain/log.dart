import 'enums.dart';

// 匹配 ANSI 转义码
final _ansiRegex = RegExp(r'\x1b\[[0-9;]*m');

/// sing-box log levels:
/// 0=Panic, 1=Fatal, 2=Error, 3=Warn, 4=Info, 5=Debug, 6=Trace
class LogEntry {
  final LogLevel type;
  final String payload;
  final DateTime timestamp;

  LogEntry({required this.type, required this.payload, required this.timestamp});

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    final rawMessage = json['message'] as String? ?? '';
    // 清理 ANSI 转义码
    final cleaned = rawMessage.replaceAll(_ansiRegex, '');
    return LogEntry(
      type: _intToLogLevel((json['level'] as num?)?.toInt() ?? 4),
      payload: cleaned,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'level': _logLevelToInt(type),
    'message': payload,
  };

  /// sing-box level: 0=Panic, 1=Fatal, 2=Error, 3=Warn, 4=Info, 5=Debug, 6=Trace
  static LogLevel _intToLogLevel(int level) => switch (level) {
    0 || 1 || 2 => LogLevel.error,
    3 => LogLevel.warning,
    4 => LogLevel.info,
    _ => LogLevel.debug,
  };

  static int _logLevelToInt(LogLevel level) => switch (level) {
    LogLevel.debug => 5,
    LogLevel.info => 4,
    LogLevel.warning => 3,
    LogLevel.error => 2,
  };
}
