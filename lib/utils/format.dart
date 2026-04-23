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