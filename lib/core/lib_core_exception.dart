class LibCoreException implements Exception {
  final String message;
  LibCoreException(this.message);

  @override
  String toString() => 'LibCoreException: $message';
}
