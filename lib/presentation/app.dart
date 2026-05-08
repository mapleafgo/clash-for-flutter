import 'package:singcast/core/lib_core.dart';
import 'package:singcast/presentation/router.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:flutter/material.dart';

class App extends StatefulWidget {
  static final routerKey = GlobalKey<NavigatorState>();

  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncVpnState();
    }
  }

  bool _syncing = false;

  Future<void> _syncVpnState() async {
    if (Constants.isDesktop || _syncing) return;
    _syncing = true;
    try {
      final running = await LibCore.instance.isVpnRunning();
      if (running != vpnConnected.value) {
        vpnConnected.value = running;
        LibCore.instance.coreConnected.value = running;
        if (!running && clashConfig.value.tunEnabled) {
          await asyncProfile();
        }
      } else if (running && LibCore.instance.proxiesSignal.value.isEmpty) {
        // VPN 运行中但代理数据为空（引擎重建后）
        try {
          final proxies = await LibCore.instance.queryProxies();
          LibCore.instance.proxiesSignal.value = proxies;
        } catch (_) {}
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Singcast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      routerConfig: router,
    );
  }
}
