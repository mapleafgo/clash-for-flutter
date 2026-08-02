import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/services/subscription.dart';

void main() {
  group('extractFilename', () {
    test('parses filename* parameter', () {
      expect(
        extractFilename("attachment; filename*=UTF-8''profile.yaml"),
        'profile.yaml',
      );
    });

    test('returns null for null header', () {
      expect(extractFilename(null), isNull);
    });
  });

  group('parseSubInfo', () {
    test('parses subscription-userinfo header', () {
      final info = parseSubInfo(
        'upload=100; download=200; total=1000; expire=1750000000',
      );
      expect(info, isNotNull);
      expect(info!.upload, 100);
      expect(info.download, 200);
      expect(info.total, 1000);
    });

    test('returns null for null header', () {
      expect(parseSubInfo(null), isNull);
    });
  });
}
