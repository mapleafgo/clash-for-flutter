import 'dart:async';
import 'dart:collection';

import 'package:clash_for_flutter/data/api/ws_streams.dart' as ws;
import 'package:clash_for_flutter/domain/enums.dart';
import 'package:clash_for_flutter/domain/log.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:intl/intl.dart';

final _logs = signal<Queue<LogEntry>>(Queue());
final _logLevel = signal(LogLevel.info);
StreamSubscription? _logSub;

void startLogSubscription() {
  effect(() {
    _logSub?.cancel();
    _logSub = ws.logsStream(_logLevel.value).listen((entry) {
      final queue = Queue<LogEntry>.from(_logs.value);
      if (queue.length >= Constants.logsCapacity) queue.removeFirst();
      queue.add(entry);
      _logs.value = queue;
    });
  });
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: '日志'),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'filter',
            mini: true,
            onPressed: _showFilter,
            child: const Icon(Icons.filter_list),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'clear',
            mini: true,
            child: const Icon(Icons.delete),
            onPressed: () => _logs.value = Queue(),
          ),
        ],
      ),
      body: Watch((context) {
        final logs = _logs.value.toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scrollController,
          itemCount: logs.length,
          itemBuilder: (_, i) {
            final log = logs[i];
            final time = DateFormat('yyyy/MM/dd HH:mm:ss')
                .format(DateTime.now());
            return SelectableText(
              '[$time] [${log.type.name.toUpperCase()}] ${log.payload}',
              style: const TextStyle(fontSize: 12),
            );
          },
        );
      }),
    );
  }

  void _showFilter() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: LogLevel.values.map((level) => ListTile(
              title: Text(level.name.toUpperCase()),
              onTap: () {
                _logLevel.value = level;
                Navigator.pop(context);
              },
            )).toList(),
      ),
    );
  }
}
