import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/core/service_manager.dart';

void main() {
  test('kLinuxSystemIpcPath and unit name are fixed', () {
    expect(kLinuxSystemIpcPath, '/run/singcast/command.sock');
    expect(kLinuxServiceUnitName, 'singcast-core.service');
  });

  test('defaultIpcPath uses home on unix and pipe on windows shape', () {
    expect(ServiceManager.defaultIpcPath('/tmp/h'), '/tmp/h/command.sock');
  });

  test(
    'LinuxServiceManager starts degraded sticky semantics via public API',
    () {
      // 纯逻辑：构造后未探测 unit，isUnitInstalled 为 false，isDegradedRun 为 false
      final sm = LinuxServiceManager('/tmp/home');
      expect(sm.isUnitInstalled, isFalse);
      expect(sm.isDegradedRun, isFalse);
      expect(sm.ipcPath, '/tmp/home/command.sock');

      sm.markDirectRun();
      // unit 未装时 direct 不算 degraded
      expect(sm.isDegradedRun, isFalse);

      sm.markSystemRun();
      expect(sm.ipcPath, kLinuxSystemIpcPath);
    },
  );

  test('linuxRunChannelFor maps TUN to system and system proxy to direct', () {
    expect(linuxRunChannelFor(tunMode: true), LinuxCoreRunMode.system);
    expect(linuxRunChannelFor(tunMode: false), LinuxCoreRunMode.direct);
  });

  test('requestDirectRun switches system channel back to direct', () {
    final sm = LinuxServiceManager('/tmp/home');
    sm.markSystemRun();
    expect(sm.runMode, LinuxCoreRunMode.system);
    expect(sm.ipcPath, kLinuxSystemIpcPath);

    sm.requestDirectRun();

    expect(sm.runMode, LinuxCoreRunMode.direct);
    expect(sm.ipcPath, ServiceManager.defaultIpcPath('/tmp/home'));
    expect(sm.isDegradedRun, isFalse);

    sm.markSystemRun();
    expect(sm.runMode, LinuxCoreRunMode.system);
    expect(sm.ipcPath, kLinuxSystemIpcPath);
  });
}
