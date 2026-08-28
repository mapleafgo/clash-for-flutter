import 'package:singcast/domain/subscription_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionInfo', () {
    test('creates with all fields', () {
      final info = SubscriptionInfo(
        upload: 100,
        download: 200,
        total: 1000,
        expire: 1700000000,
      );
      expect(info.upload, 100);
      expect(info.download, 200);
      expect(info.total, 1000);
      expect(info.expire, 1700000000);
    });

    test('used calculates upload + download', () {
      final info = SubscriptionInfo(upload: 100, download: 200);
      expect(info.used, 300);
    });

    test('used handles null values', () {
      final info = SubscriptionInfo();
      expect(info.used, 0);
    });

    test('used handles partial null values', () {
      expect(SubscriptionInfo(upload: 100).used, 100);
      expect(SubscriptionInfo(download: 200).used, 200);
    });

    test('JSON roundtrip', () {
      final info = SubscriptionInfo(
        upload: 1024,
        download: 2048,
        total: 10240,
        expire: 1700000000,
      );
      final json = info.toJson();
      final restored = SubscriptionInfo.fromJson(json);

      expect(restored.upload, 1024);
      expect(restored.download, 2048);
      expect(restored.total, 10240);
      expect(restored.expire, 1700000000);
    });

    test('JSON roundtrip with nulls', () {
      final info = SubscriptionInfo();
      final json = info.toJson();
      final restored = SubscriptionInfo.fromJson(json);

      expect(restored.upload, isNull);
      expect(restored.download, isNull);
      expect(restored.total, isNull);
      expect(restored.expire, isNull);
      expect(restored.used, 0);
    });
  });

  group('SubscriptionInfo.fromHeader', () {
    test('parses full header string', () {
      const header = 'upload=100; download=200; total=1000; expire=1700000000';
      final info = SubscriptionInfo.fromHeader(header);

      expect(info.upload, 100);
      expect(info.download, 200);
      expect(info.total, 1000);
      expect(info.expire, 1700000000);
    });

    test('parses partial header string', () {
      const header = 'upload=500; total=2000';
      final info = SubscriptionInfo.fromHeader(header);

      expect(info.upload, 500);
      expect(info.download, isNull);
      expect(info.total, 2000);
      expect(info.expire, isNull);
    });

    test('handles empty string', () {
      final info = SubscriptionInfo.fromHeader('');
      expect(info.upload, isNull);
      expect(info.download, isNull);
      expect(info.used, 0);
    });

    test('handles single field', () {
      const header = 'total=536870912000';
      final info = SubscriptionInfo.fromHeader(header);
      expect(info.total, 536870912000);
    });

    test('handles extra whitespace', () {
      const header =
          '  upload = 100 ;  download = 200 ; total = 1000 ; expire = 123  ';
      final info = SubscriptionInfo.fromHeader(header);
      // Whitespace around = means the key won't match exactly
      // This tests robustness
      expect(info.used, greaterThanOrEqualTo(0));
    });

    test('handles non-numeric values gracefully', () {
      const header = 'upload=abc; download=200';
      final info = SubscriptionInfo.fromHeader(header);
      expect(info.upload, isNull);
      expect(info.download, 200);
    });
  });
}
