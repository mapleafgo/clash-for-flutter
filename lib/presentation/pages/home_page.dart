import 'dart:async';

import 'package:clash_for_flutter/data/api/ws_streams.dart' as ws;
import 'package:clash_for_flutter/domain/net_speed.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/app_config.dart';
import 'package:clash_for_flutter/services/core_config.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:clash_for_flutter/utils/format.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

const _btnSize = Size(200, 70);

final _speed = signal(NetSpeed());

void startTrafficSubscription() {
  ws.trafficStream().listen((s) => _speed.value = s);
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: 'Clash for Flutter'),
      body: Center(
        child: Watch((context) {
          final enabled = tunIf.value!
              ? clashConfig.value.tunEnabled
              : systemProxy.value;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _ToggleBtn(enabled: enabled),
            const SizedBox(height: 16),
            _SpeedDisplay(),
            if (Constants.isDesktop) ...[
              const SizedBox(height: 24),
              _TunSwitch(),
            ],
          ]);
        }),
      ),
    );
  }
}

class _SpeedDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final speed = _speed.value;
      return Text(
        '↑ ${formatBytes(speed.up)}/s  ↓ ${formatBytes(speed.down)}/s',
        style: const TextStyle(fontSize: 14),
      );
    });
  }
}

class _ToggleBtn extends StatefulWidget {
  final bool enabled;
  const _ToggleBtn({required this.enabled});
  @override
  State<_ToggleBtn> createState() => _ToggleBtnState();
}

class _ToggleBtnState extends State<_ToggleBtn> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox.fromSize(
        size: _btnSize,
        child: const Card(
          color: Colors.grey,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return SizedBox.fromSize(
      size: _btnSize,
      child: Card(
        color: widget.enabled ? Colors.green : null,
        child: InkWell(
          onTap: _toggle,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.enabled ? Icons.flight_land : Icons.flight_takeoff),
            Text(widget.enabled ? '关闭' : '开启'),
          ]),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      if (tunIf.value!) {
        await (clashConfig.value.tunEnabled ? closeTun() : openTun());
      } else {
        await (systemProxy.value ? closeProxy() : openProxy());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _TunSwitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Watch((context) => SwitchListTile(
          title: const Text('TUN 模式'),
          subtitle: const Text('需要管理员权限'),
          value: clashConfig.value.tunEnabled,
          onChanged: (v) async {
            await (v ? openTun() : closeTun());
          },
        ));
  }
}
