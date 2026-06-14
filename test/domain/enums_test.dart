import 'package:singcast/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Enums', () {
    test('Mode has expected values', () {
      expect(Mode.values, [Mode.rule, Mode.global, Mode.direct]);
    });

    test('LogLevel has expected values', () {
      expect(LogLevel.values, [
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]);
    });

    test('ProfileType has expected values', () {
      expect(ProfileType.values, [ProfileType.url, ProfileType.file]);
    });

    test('SortType has expected values', () {
      expect(SortType.values, [
        SortType.defaults,
        SortType.name,
        SortType.delay,
      ]);
    });

    test('enum names are accessible', () {
      expect(Mode.rule.name, 'rule');
      expect(LogLevel.info.name, 'info');
      expect(ProfileType.url.name, 'url');
    });
  });
}
