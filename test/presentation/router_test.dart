import 'package:singcast/presentation/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Routes', () {
    test('all route paths start with /', () {
      expect(Routes.home, startsWith('/'));
      expect(Routes.proxies, startsWith('/'));
      expect(Routes.logs, startsWith('/'));
      expect(Routes.profiles, startsWith('/'));
      expect(Routes.settings, startsWith('/'));
    });

    test('route paths are unique', () {
      final paths = [
        Routes.home,
        Routes.proxies,
        Routes.logs,
        Routes.profiles,
        Routes.settings,
      ];
      expect(paths.toSet().length, paths.length);
    });

    test('route paths match expected values', () {
      expect(Routes.home, '/home');
      expect(Routes.proxies, '/proxies');
      expect(Routes.logs, '/logs');
      expect(Routes.profiles, '/profiles');
      expect(Routes.settings, '/settings');
    });
  });

  group('NavItem', () {
    test('navItems has correct count', () {
      expect(navItems.length, 5);
    });

    test('navItems paths match Routes constants', () {
      expect(navItems[0].path, Routes.home);
      expect(navItems[1].path, Routes.proxies);
      expect(navItems[2].path, Routes.profiles);
      expect(navItems[3].path, Routes.logs);
      expect(navItems[4].path, Routes.settings);
    });

    test('navItems labels are not empty', () {
      for (final item in navItems) {
        expect(item.label, isNotEmpty);
      }
    });

    test('navItems icons are distinct IconData', () {
      final icons = navItems.map((e) => e.icon).toSet();
      expect(icons.length, navItems.length);
    });

    test('NavItem stores path, label, icon', () {
      const item = NavItem('/test', 'Test', Icons.ac_unit);
      expect(item.path, '/test');
      expect(item.label, 'Test');
      expect(item.icon, Icons.ac_unit);
    });
  });

  group('router', () {
    test('router is configured', () {
      expect(router, isNotNull);
    });

    test('router has routes configured', () {
      expect(router.configuration.routes, isNotEmpty);
    });
  });
}
