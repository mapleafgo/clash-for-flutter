import 'package:singcast/core/lib_core.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/presentation/widgets/sys_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:intl/intl.dart';

final _logLevel = signal(LogLevel.info);

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _scrollController = ScrollController();
  bool _isAtBottom = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: '日志'),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isAtBottom) ...[
            FloatingActionButton(
              heroTag: 'scrollBottom',
              onPressed: _scrollToBottom,
              tooltip: '回到底部',
              child: const Icon(Icons.arrow_downward),
            ),
            const SizedBox(width: 8),
          ],
          FloatingActionButton(
            heroTag: 'filter',
            onPressed: _showFilter,
            tooltip: '过滤',
            child: const Icon(Icons.filter_list),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            heroTag: 'clear',
            tooltip: '清除',
            onPressed: () => LibCore.instance.clearLogs(),
            child: const Icon(Icons.delete),
          ),
        ],
      ),
      body: Watch((context) {
        final allLogs = LibCore.instance.logsSignal.value;
        final minLevel = _logLevel.value;
        final logs = allLogs.where((e) {
          return _logLevelToInt(e.type) >= _logLevelToInt(minLevel);
        }).toList();
        if (_isAtBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                  _scrollController.position.maxScrollExtent);
            }
          });
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (!_scrollController.hasClients) return false;
            final max = _scrollController.position.maxScrollExtent;
            final current = _scrollController.position.pixels;
            final atBottom = (max - current) <= 50;
            if (atBottom != _isAtBottom) {
              setState(() => _isAtBottom = atBottom);
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final log = logs[i];
              final time = DateFormat('yyyy/MM/dd HH:mm:ss').format(log.timestamp);
              return SelectableText(
                '[$time] [${log.type.name.toUpperCase()}] ${log.payload}',
                style: const TextStyle(fontSize: 12),
              );
            },
          ),
        );
      }),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  int _logLevelToInt(LogLevel level) => switch (level) {
    LogLevel.debug => 0,
    LogLevel.info => 1,
    LogLevel.warning => 2,
    LogLevel.error => 3,
  };

  void _showFilter() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('日志级别'),
        children: LogLevel.values.map((level) => ListTile(
              title: Text(level.name.toUpperCase()),
              selected: _logLevel.value == level,
              onTap: () {
                _logLevel.value = level;
                Navigator.pop(ctx);
              },
            )).toList(),
      ),
    );
  }
}
