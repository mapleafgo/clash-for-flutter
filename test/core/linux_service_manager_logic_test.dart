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

  test('LinuxServiceManager starts degraded sticky semantics via public API', () {
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
  });
}
