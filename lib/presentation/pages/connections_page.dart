import 'package:clash_for_flutter/data/api/ws_streams.dart' as ws;
import 'package:clash_for_flutter/domain/connection.dart';
import 'package:clash_for_flutter/presentation/widgets/sys_app_bar.dart';
import 'package:clash_for_flutter/services/clash_api.dart';
import 'package:clash_for_flutter/utils/format.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

final _connections = signal<List<Connection>>([]);
final _prevConnections = signal<Map<String, Connection>>({});

void startConnectionsSubscription() {
  ws.connectionsStream().listen((snapshot) {
    final prev = {for (final c in _connections.value) c.id: c};
    _prevConnections.value = prev;
    _connections.value = snapshot.connections
      ..sort((a, b) => b.start.compareTo(a.start));
  });
}

class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: '连接'),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.close),
        onPressed: () async {
          await api.closeAllConnections();
        },
      ),
      body: Watch((context) {
        final conns = _connections.value;
        final prev = _prevConnections.value;
        return PaginatedDataTable2(
          columns: const [
            DataColumn2(label: Text('域名'), size: ColumnSize.L),
            DataColumn2(label: Text('网络'), size: ColumnSize.S),
            DataColumn2(label: Text('类型'), size: ColumnSize.M),
            DataColumn2(label: Text('节点链'), size: ColumnSize.L),
            DataColumn2(label: Text('规则'), size: ColumnSize.L),
            DataColumn2(label: Text('进程'), size: ColumnSize.S),
            DataColumn2(label: Text('速率'), size: ColumnSize.M),
            DataColumn2(label: Text('上传'), size: ColumnSize.S),
            DataColumn2(label: Text('下载'), size: ColumnSize.S),
            DataColumn2(label: Text('来源IP'), size: ColumnSize.S),
            DataColumn2(label: Text('连接时间'), size: ColumnSize.M),
          ],
          source: _ConnSource(conns, prev, context),
          rowsPerPage: 20,
          minWidth: 1200,
        );
      }),
    );
  }
}

class _ConnSource extends DataTableSource {
  final List<Connection> conns;
  final Map<String, Connection> prev;
  final BuildContext context;

  _ConnSource(this.conns, this.prev, this.context);

  @override
  int get rowCount => conns.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;

  @override
  DataRow getRow(int index) {
    final c = conns[index];
    final old = prev[c.id];
    final speedDown = old != null ? c.download - old.download : 0;
    final speedUp = old != null ? c.upload - old.upload : 0;
    final host = c.metadata.host.isNotEmpty
        ? c.metadata.host
        : c.metadata.destinationIP;

    return DataRow(cells: [
      DataCell(Text(host), onTap: () => _showDetail(context, c)),
      DataCell(Text(c.metadata.network)),
      DataCell(Text(c.metadata.type)),
      DataCell(Text(c.chains.join(' → '))),
      DataCell(Text(c.rule)),
      DataCell(Text(c.metadata.process)),
      DataCell(Text('↑${formatBytes(speedUp)} ↓${formatBytes(speedDown)}/s')),
      DataCell(Text(formatBytes(c.upload))),
      DataCell(Text(formatBytes(c.download))),
      DataCell(Text(c.metadata.sourceIP)),
      DataCell(Text(timeago.format(DateTime.tryParse(c.start) ?? DateTime.now(), locale: 'zh_cn'))),
    ]);
  }

  void _showDetail(BuildContext context, Connection c) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.metadata.host),
        content: Table(
          children: [
            _row('ID', c.id),
            _row('Network', c.metadata.network),
            _row('Type', c.metadata.type),
            _row('Host', c.metadata.host),
            _row('Destination IP', c.metadata.destinationIP),
            _row('Source IP', c.metadata.sourceIP),
            _row('Process', c.metadata.processPath),
            _row('Rule', c.rule),
            _row('Upload', formatBytes(c.upload)),
            _row('Download', formatBytes(c.download)),
            _row('Status', '连接中'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await api.closeConnection(c.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('关闭连接'),
          ),
        ],
      ),
    );
  }

  TableRow _row(String label, String value) => TableRow(
        children: [Padding(
          padding: const EdgeInsets.all(4),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ), Padding(
          padding: const EdgeInsets.all(4),
          child: Text(value),
        )],
      );
}
