import 'dart:async';

import 'package:clash_for_flutter/app/bean/connection_bean.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/pages/connections/connection_bean.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:clash_for_flutter/app/utils/utils.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:timeago/timeago.dart' as timeago;

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final _request = Modular.get<Request>();
  final ScrollController _controller = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  StreamSubscription? _subscription;
  Snapshot _snapshot = Snapshot.empty();
  List<ConnectionShow> _data = [];
  bool _showFab = true;

  @override
  void initState() {
    super.initState();
    _subscription = _request.connections().listen((event) {
      setState(() {
        var newSnapshot = event ?? Snapshot.empty();
        _data = toShow(_snapshot.connections, newSnapshot.connections);
        _snapshot = newSnapshot;
      });
    });
    _controller.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_controller.position.userScrollDirection == ScrollDirection.reverse && _showFab) {
      setState(() => _showFab = false);
    }
    if (_controller.position.userScrollDirection == ScrollDirection.forward && !_showFab) {
      setState(() => _showFab = true);
    }
  }

  List<ConnectionShow> toShow(List<Connection> oldValue, List<Connection> newValue) {
    var result = <ConnectionShow>[];
    // 对数据进行按时间排序
    newValue.sort((a, b) => DateTime.parse(a.start).compareTo(DateTime.parse(b.start)));
    for (var c in newValue) {
      var o = oldValue.firstWhere((element) => element.id == c.id, orElse: () => Connection.empty());
      var speed = StringBuffer();
      if (o.id != "") {
        if (c.upload - o.upload != 0) {
          speed.write("↑ ${dataformat(c.upload - o.upload)}/s");
        }
        if (c.download - o.download != 0) {
          if (speed.isNotEmpty) speed.write("\n");
          speed.write("↓ ${dataformat(c.download - o.download)}/s");
        }
      }
      if (speed.isEmpty) speed.write("-");
      result.add(ConnectionShow(
        id: c.id,
        host: c.metadata.host == "" ? "${c.metadata.destinationIP}:${c.metadata.destinationPort}" : c.metadata.host,
        network: c.metadata.network.toUpperCase(),
        type: c.metadata.type,
        chains: c.chains.join(" / "),
        rule: c.rulePayload != "" ? "${c.rule} :: ${c.rulePayload}" : c.rule,
        process: c.metadata.processPath,
        upload: dataformat(c.upload),
        download: dataformat(c.download),
        sourceIP: c.metadata.sourceIP,
        time: timeago.format(DateTime.parse(c.start), locale: "zh_cn"),
        speed: speed.toString(),
      ));
    }
    return result;
  }

  detail(int index) {
    showDialog(
      context: context,
      builder: (cxt) {
        var connection = _snapshot.connections[index];
        var completed = _data.any((e) => e.id == connection.id);
        return AlertDialog(
          content: Container(
            constraints: const BoxConstraints(minWidth: 360.0),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(100),
                1: FlexColumnWidth(600),
              },
              children: [
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("ID")),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(connection.id)),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("网络")),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(connection.metadata.network.toUpperCase())),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("类型")),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(connection.metadata.type)),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("域名")),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text("${connection.metadata.host}:${connection.metadata.destinationPort}"),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("IP")),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        connection.metadata.destinationIP != ""
                            ? "${connection.metadata.destinationIP}:${connection.metadata.destinationPort}"
                            : "-",
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("来源")),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text("${connection.metadata.sourceIP}:${connection.metadata.sourcePort}"),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("进程")),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6), child: Text(connection.metadata.processPath)),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("路径")),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6), child: Text(connection.metadata.processPath)),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("规则")),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(connection.rulePayload != ""
                          ? "${connection.rule} :: ${connection.rulePayload}"
                          : connection.rule),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("代理")),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6), child: Text(connection.chains.join(" / "))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("上传")),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6), child: Text(dataformat(connection.upload))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("下载")),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6), child: Text(dataformat(connection.download))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text("状态")),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: completed
                          ? const Text("连接中", style: TextStyle(color: Colors.green))
                          : const Text("已断开", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          title: const Text("连接信息"),
          actions: [
            TextButton(
              child: const Text("取消"),
              onPressed: () => Navigator.of(cxt).pop(),
            ),
            TextButton(
              child: const Text("断开连接"),
              onPressed: () {
                _request.closeConnections(connection.id);
                Navigator.of(cxt).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: Row(
          children: [
            const Text("连接"),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                "(总量: 上传 ${dataformat(_snapshot.uploadTotal)} / 下载 ${dataformat(_snapshot.downloadTotal)})",
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Theme(
            data: ThemeData(
              scrollbarTheme: ScrollbarThemeData(
                  thumbVisibility: MaterialStateProperty.all(true),
                  thumbColor: MaterialStateProperty.all<Color>(Colors.black26)),
            ),
            child: DataTable2(
                scrollController: _controller,
                horizontalScrollController: _horizontalController,
                columnSpacing: 6,
                horizontalMargin: 6,
                minWidth: 1500,
                smRatio: 0.8,
                lmRatio: 2,
                columns: const [
                  DataColumn2(
                    label: Text("域名"),
                    size: ColumnSize.L,
                  ),
                  DataColumn2(
                    label: Text("网络"),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text("类型"),
                    size: ColumnSize.M,
                  ),
                  DataColumn2(
                    label: Text("节点链"),
                    size: ColumnSize.L,
                  ),
                  DataColumn2(
                    label: Text("规则"),
                    size: ColumnSize.L,
                  ),
                  DataColumn2(
                    label: Text("进程"),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text("速率"),
                    size: ColumnSize.M,
                  ),
                  DataColumn2(
                    label: Text("上传"),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text("下载"),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text("来源IP"),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text("连接时间"),
                    size: ColumnSize.M,
                  ),
                ],
                rows: List<DataRow2>.generate(_data.length, (index) {
                  var c = _data[index];
                  return DataRow2(
                    onTap: () => detail(index),
                    cells: [
                      DataCell(Text(c.host)),
                      DataCell(Text(c.network)),
                      DataCell(Text(c.type)),
                      DataCell(Text(
                        c.chains,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )),
                      DataCell(Text(
                        c.rule,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )),
                      DataCell(Text(c.process)),
                      DataCell(Text(c.speed)),
                      DataCell(Text(c.upload)),
                      DataCell(Text(c.download)),
                      DataCell(Text(c.sourceIP)),
                      DataCell(Text(c.time)),
                    ],
                  );
                })),
          )
        ],
      ),
      floatingActionButton: _showFab
          ? FloatingActionButton(
              tooltip: "断开所有连接",
              child: const Icon(Icons.clear_all),
              onPressed: () => _request.closeAllConnections(),
            )
          : null,
    );
  }
}
