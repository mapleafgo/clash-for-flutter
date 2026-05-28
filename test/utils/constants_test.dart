import 'package:singcast/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Constants', () {
    test('profilesPath is /profiles', () {
      expect(Constants.profilesPath, '/profiles');
    });

    test('clashConfig is /config.yaml', () {
      expect(Constants.clashConfig, '/config.yaml');
    });

    test('appSettings is /settings.json', () {
      expect(Constants.appSettings, '/settings.json');
    });

    test('localhost is 127.0.0.1', () {
      expect(Constants.localhost, '127.0.0.1');
    });

    test('logsCapacity is 1000', () {
      expect(Constants.logsCapacity, 1000);
    });

    test('sourceUrl points to GitHub', () {
      expect(Constants.sourceUrl, contains('github.com'));
      expect(Constants.sourceUrl, contains('singcast'));
    });

    test('homeUrl is valid', () {
      expect(Constants.homeUrl, contains('singcast'));
    });

    test('releaseUrl is GitHub API', () {
      expect(Constants.releaseUrl, contains('api.github.com'));
      expect(Constants.releaseUrl, contains('releases/latest'));
    });
  });

  group('Defaults', () {
    test('delayTestUrl is gstatic generate_204', () {
      expect(Defaults.delayTestUrl, contains('gstatic.com'));
      expect(Defaults.delayTestUrl, contains('generate_204'));
    });
  });
}
