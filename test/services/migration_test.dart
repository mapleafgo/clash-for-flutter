import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/services/migration.dart';
import 'package:singcast/utils/constants.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('singcast-migrate-test');
    Constants.homeDir = tmp;
    final profiles = Directory(p.join(tmp.path, 'profiles'));
    profiles.createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'migrates settings and file profile, deletes config.yaml marker',
    () async {
      File(
        p.join(tmp.path, 'config.yaml'),
      ).writeAsStringSync('mixed-port: 8080\nmode: global\n');
      final oldProfile = '123.yaml';
      File(
        p.join(tmp.path, 'profiles', oldProfile),
      ).writeAsStringSync('proxies:\n  - name: p\n    type: ss\n');
      AppSettingsStorage.save({
        'profiles': [
          {
            'file': oldProfile,
            'name': 'legacy',
            'type': 'file',
            'time': '2026-08-02T00:00:00.000',
          },
        ],
      });

      await migrateLegacy(
        convert: (_) async => '{"outbounds":[]}',
        validate: (_) async {},
      );

      expect(File(p.join(tmp.path, 'config.yaml')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'config.json')).existsSync(), isTrue);
      final stored = AppSettingsStorage.load()['profiles'] as List;
      final saved = stored.single as Map<String, dynamic>;
      expect((saved['file'] as String).endsWith('.json'), isTrue);
      expect(
        File(p.join(tmp.path, 'profiles', oldProfile)).existsSync(),
        isFalse,
      );
    },
  );

  test('skips when config.yaml missing', () async {
    AppSettingsStorage.save({'profiles': []});
    await migrateLegacy(convert: (_) async => '{}');
    expect(File(p.join(tmp.path, 'config.json')).existsSync(), isFalse);
  });

  test('url profile converts local file without refreshing', () async {
    File(
      p.join(tmp.path, 'config.yaml'),
    ).writeAsStringSync('mixed-port: 7890\n');
    final oldProfile = '456.yaml';
    File(
      p.join(tmp.path, 'profiles', oldProfile),
    ).writeAsStringSync('proxies:\n  - name: p\n    type: ss\n');
    AppSettingsStorage.save({
      'profiles': [
        {
          'file': oldProfile,
          'name': 'legacy-url',
          'type': 'url',
          'time': '2026-08-02T00:00:00.000',
          'url': 'https://example.com/sub',
          'interval': 24,
        },
      ],
    });

    await migrateLegacy(
      convert: (_) async => '{"outbounds":[]}',
      validate: (_) async {},
    );

    expect(File(p.join(tmp.path, 'config.yaml')).existsSync(), isFalse);
    final stored = AppSettingsStorage.load()['profiles'] as List;
    final saved = stored.single as Map<String, dynamic>;
    expect(saved['type'], 'url');
    expect(saved['url'], 'https://example.com/sub');
    expect((saved['file'] as String).endsWith('.json'), isTrue);
    expect(
      File(p.join(tmp.path, 'profiles', oldProfile)).existsSync(),
      isFalse,
    );
  });

  test('keeps config.yaml marker when a profile fails to migrate', () async {
    File(
      p.join(tmp.path, 'config.yaml'),
    ).writeAsStringSync('mixed-port: 7890\n');
    final oldProfile = '789.yaml';
    File(
      p.join(tmp.path, 'profiles', oldProfile),
    ).writeAsStringSync('proxies:\n  - name: p\n    type: ss\n');
    AppSettingsStorage.save({
      'profiles': [
        {
          'file': oldProfile,
          'name': 'legacy',
          'type': 'file',
          'time': '2026-08-02T00:00:00.000',
        },
      ],
    });

    await migrateLegacy(
      convert: (_) async => throw Exception('bad content'),
      validate: (_) async {},
    );

    expect(File(p.join(tmp.path, 'config.yaml')).existsSync(), isTrue);
    expect(File(p.join(tmp.path, 'config.json')).existsSync(), isTrue);
  });
}
