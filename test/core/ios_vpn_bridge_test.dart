import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/core/ipc_worker.dart';

void main() {
  group('IosVpnBridge logic tests', () {
    test('IpcWorker VPN lifecycle hooks are nullable', () {
      final worker = IpcWorker(ipcPath: '/tmp/test.sock');

      // Verify all hooks start as null
      expect(worker.connectVpnImpl, isNull);
      expect(worker.disconnectVpnImpl, isNull);
      expect(worker.isVpnRunningImpl, isNull);
      expect(worker.startCoreWithContentImpl, isNull);
    });

    test('IpcWorker connectVpn throws when hook not set', () async {
      final worker = IpcWorker(ipcPath: '/tmp/test.sock');

      expect(
        () => worker.connectVpn('config'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('IpcWorker disconnectVpn throws when hook not set', () async {
      final worker = IpcWorker(ipcPath: '/tmp/test.sock');

      expect(
        () => worker.disconnectVpn(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('IpcWorker isVpnRunning returns false when hook not set', () async {
      final worker = IpcWorker(ipcPath: '/tmp/test.sock');

      final result = await worker.isVpnRunning();
      expect(result, isFalse);
    });

    test('IpcWorker uses injected hook when set', () async {
      final worker = IpcWorker(ipcPath: '/tmp/test.sock');
      var called = false;

      worker.connectVpnImpl = (config, {ruleSetProxy, ipv6}) async {
        called = true;
        expect(config, equals('test-config'));
        expect(ruleSetProxy, equals('proxy'));
        expect(ipv6, isTrue);
      };

      await worker.connectVpn('test-config', ruleSetProxy: 'proxy', ipv6: true);
      expect(called, isTrue);
    });

    test('IpcWorker startCoreWithContent uses hook when set', () async {
      final worker = IpcWorker(ipcPath: '/tmp/test.sock');
      var called = false;

    worker.startCoreWithContentImpl = (content, {ruleSetProxy, enabledVpn = false}) async {
      called = true;
      expect(content, equals('new-config'));
      expect(ruleSetProxy, equals('proxy'));
      // enabledVpn is not forwarded to the iOS hook (Extension handles VPN internally)
    };

      await worker.startCoreWithContent('new-config', ruleSetProxy: 'proxy', enabledVpn: true);
      expect(called, isTrue);
    });

    test('appGroupSocketPath path concatenation logic', () {
      // Test the path concatenation logic that would be in IosVpnBridge
      String buildSocketPath(String container) {
        const socketName = 'command.sock';
        return container.endsWith('/')
            ? '$container$socketName'
            : '$container/$socketName';
      }

      expect(
        buildSocketPath('/var/mobile/Containers/Shared/AppGroup/group.test/'),
        equals('/var/mobile/Containers/Shared/AppGroup/group.test/command.sock'),
      );

      expect(
        buildSocketPath('/var/mobile/Containers/Shared/AppGroup/group.test'),
        equals('/var/mobile/Containers/Shared/AppGroup/group.test/command.sock'),
      );
    });
  });
}
