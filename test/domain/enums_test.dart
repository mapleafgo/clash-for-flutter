import 'package:singcast/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isUsedProxy', () {
    test('returns true for DIRECT', () {
      expect(isUsedProxy('DIRECT'), true);
    });

    test('returns true for REJECT', () {
      expect(isUsedProxy('REJECT'), true);
    });

    test('returns true for GLOBAL', () {
      expect(isUsedProxy('GLOBAL'), true);
    });

    test('returns false for normal proxy names', () {
      expect(isUsedProxy('HK-01'), false);
      expect(isUsedProxy('US-Proxy'), false);
      expect(isUsedProxy(''), false);
    });

    test('is case sensitive', () {
      expect(isUsedProxy('direct'), false);
      expect(isUsedProxy('Direct'), false);
    });
  });

  group('isGroupType', () {
    test('returns true for Selector', () {
      expect(isGroupType('Selector'), true);
    });

    test('returns true for URLTest', () {
      expect(isGroupType('URLTest'), true);
    });

    test('returns true for Fallback', () {
      expect(isGroupType('Fallback'), true);
    });

    test('returns true for LoadBalance', () {
      expect(isGroupType('LoadBalance'), true);
    });

    test('returns false for non-group types', () {
      expect(isGroupType('Shadowsocks'), false);
      expect(isGroupType('VMess'), false);
      expect(isGroupType(''), false);
    });

    test('is case sensitive', () {
      expect(isGroupType('selector'), false);
      expect(isGroupType('urltest'), false);
    });
  });

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

    test('GroupType has expected values', () {
      expect(GroupType.values, [
        GroupType.selector,
        GroupType.urlTest,
        GroupType.fallback,
        GroupType.loadBalance,
      ]);
    });

    test('enum names are accessible', () {
      expect(Mode.rule.name, 'rule');
      expect(LogLevel.info.name, 'info');
      expect(ProfileType.url.name, 'url');
    });
  });
}
