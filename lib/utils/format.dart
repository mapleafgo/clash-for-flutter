String formatBytes(int value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  double num = value.toDouble();
  var level = 0;
  while (num > 1024 && level < units.length - 1) {
    num /= 1024;
    level++;
  }
  return "${num.toStringAsFixed(1)} ${units[level]}";
}

String formatDuration(int startedAtMs) {
  if (startedAtMs <= 0) return '00:00';
  final diff = DateTime.now().millisecondsSinceEpoch - startedAtMs;
  if (diff < 0) return '00:00';
  final duration = Duration(milliseconds: diff);
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60);
  final s = duration.inSeconds.remainder(60);
  if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}