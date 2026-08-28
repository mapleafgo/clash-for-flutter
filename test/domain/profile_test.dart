import 'dart:convert';

import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/domain/subscription_info.dart';
import 'package:flutter_test/flutter_test.dart';

T _roundtrip<T>(
  T obj,
  T Function(Map<String, dynamic>) fromJson,
  Map<String, dynamic> Function(T) toJson,
) {
  return fromJson(jsonDecode(jsonEncode(toJson(obj))) as Map<String, dynamic>);
}

void main() {
  group('Profile', () {
    final testTime = DateTime(2024, 1, 15, 10, 30, 0);

    test('creates with required fields', () {
      final profile = Profile(
        file: 'test.yaml',
        name: 'Test',
        type: ProfileType.url,
        time: testTime,
      );
      expect(profile.file, 'test.yaml');
      expect(profile.name, 'Test');
      expect(profile.type, ProfileType.url);
      expect(profile.time, testTime);
      expect(profile.url, isNull);
      expect(profile.interval, 0);
      expect(profile.userinfo, isNull);
    });

    test('creates with all fields', () {
      final info = SubscriptionInfo(upload: 100, download: 200, total: 1000);
      final profile = Profile(
        file: 'sub.yaml',
        name: 'My Sub',
        type: ProfileType.url,
        time: testTime,
        url: 'https://example.com/sub',
        interval: 24,
        userinfo: info,
      );
      expect(profile.url, 'https://example.com/sub');
      expect(profile.interval, 24);
      expect(profile.userinfo?.total, 1000);
    });

    test('JSON roundtrip for url type', () {
      final profile = Profile(
        file: '123.yaml',
        name: 'Subscription',
        type: ProfileType.url,
        time: testTime,
        url: 'https://example.com/sub',
        interval: 12,
      );
      final restored = _roundtrip(profile, Profile.fromJson, (p) => p.toJson());

      expect(restored.file, profile.file);
      expect(restored.name, profile.name);
      expect(restored.type, ProfileType.url);
      expect(restored.url, profile.url);
      expect(restored.interval, 12);
    });

    test('JSON roundtrip for file type', () {
      final profile = Profile(
        file: 'local.yaml',
        name: 'Local',
        type: ProfileType.file,
        time: testTime,
      );
      final restored = _roundtrip(profile, Profile.fromJson, (p) => p.toJson());

      expect(restored.type, ProfileType.file);
      expect(restored.url, isNull);
      expect(restored.interval, 0);
    });

    test('JSON roundtrip with userinfo', () {
      final info = SubscriptionInfo(
        upload: 1024,
        download: 2048,
        total: 10240,
        expire: 1700000000,
      );
      final profile = Profile(
        file: 'sub.yaml',
        name: 'With Info',
        type: ProfileType.url,
        time: testTime,
        userinfo: info,
      );
      final restored = _roundtrip(profile, Profile.fromJson, (p) => p.toJson());

      expect(restored.userinfo, isNotNull);
      expect(restored.userinfo!.upload, 1024);
      expect(restored.userinfo!.download, 2048);
      expect(restored.userinfo!.total, 10240);
    });

    test('fromJson parses external JSON correctly', () {
      final profile = Profile.fromJson({
        'file': 'abc.yaml',
        'name': 'Test',
        'type': 'url',
        'time': testTime.toIso8601String(),
        'url': 'https://example.com',
        'interval': 24,
      });

      expect(profile.file, 'abc.yaml');
      expect(profile.type, ProfileType.url);
      expect(profile.interval, 24);
    });
  });
}
