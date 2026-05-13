import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/presentation/router.dart';
import 'package:singcast/services/app_config.dart';
import 'package:singcast/services/core_config.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:singcast/domain/enums.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

final appReady = signal(false);

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
      LogFileWriter.instance?.log(
        '_syncVpnState: running=$running vpnConnected=${vpnConnected.value} tunEnabled=${clashConfig.value.tunEnabled}',
        name: 'tun',
      );
      if (running != vpnConnected.value) {
        vpnConnected.value = running;
        if (!running && clashConfig.value.tunEnabled) {
          LogFileWriter.instance?.log(
            '_syncVpnState: VPN stopped but tunEnabled, calling asyncProfile',
            level: LogLevel.warning,
            name: 'tun',
          );
          await asyncProfile();
        }
      } else if (running && LibCore.instance.proxiesSignal.value.isEmpty) {
        LogFileWriter.instance?.log('_syncVpnState: VPN running but proxies empty, re-querying', name: 'tun');
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
    return Watch((context) {
      final ready = appReady.value;
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
        themeMode: resolvedThemeMode,
        routerConfig: ready ? router : _splashRouter,
      );
    });
  }
}

final _splashRouter = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const _SplashPage()),
]);

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1B1F) : Colors.white;
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SvgPicture.asset('assets/logo.svg', width: 120, height: 120),
      ),
    );
  }
}
