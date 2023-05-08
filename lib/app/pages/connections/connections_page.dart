import 'dart:async';

import 'package:clash_for_flutter/app/bean/connection_bean.dart';
import 'package:clash_for_flutter/app/component/sys_app_bar.dart';
import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/connections/connection_bean.dart';
import 'package:clash_for_flutter/app/source/request.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:timeago/timeago.dart' as timeago;

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('zh_cn', timeago.ZhCnMessages());
    _subscription = _request.connections().listen((event) {
      setState(() {
        var newSnapshot = event ?? Snapshot.empty();
        _data = toShow(_snapshot.connections, newSnapshot.connections);
        _snapshot = newSnapshot;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  List<ConnectionShow> toShow(List<Connection> oldValue, List<Connection> newValue) {
    var result = <ConnectionShow>[];
    for (var c in newValue) {
      var o = oldValue.firstWhere((element) => element.id == c.id, orElse: () => Connection.empty());
      var speed = StringBuffer();
      if (o.id == "") {
        speed.write("-");
      } else {
        if (c.upload - o.upload != 0) {
          speed.write("↑ ${format(c.upload - o.upload)}/s");
        }
        if (c.download - o.download != 0) {
          if (speed.isNotEmpty) speed.write("\n");
          speed.write("↓ ${format(c.download - o.download)}/s");
        }
        if (speed.isEmpty) speed.write("-");
      }
      result.add(ConnectionShow(
        host: c.metadata.host == "" ? "${c.metadata.destinationIP}:${c.metadata.destinationPort}" : c.metadata.host,
        network: c.metadata.network.toUpperCase(),
        type: c.metadata.type,
        chains: c.chains.join(" / "),
        rule: c.rulePayload != "" ? "${c.rule} :: ${c.rulePayload}" : c.rule,
        process: c.metadata.processPath,
        upload: format(c.upload),
        download: format(c.download),
        sourceIP: c.metadata.sourceIP,
        time: timeago.format(DateTime.parse(c.start), locale: "zh_cn"),
        speed: speed.toString(),
      ));
    }
    return result;
  }

  String format(int value) {
    double num = value.toDouble();
    var level = 0;
    for (; num.compareTo(1024) > 0; level++) {
      num /= 1024;
    }
    return "${num.toStringAsFixed(1)} ${DataUnit.values[level].value}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text("连接")),
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
                bottomMargin: 50,
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
                  return DataRow2(cells: [
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
                  ]);
                })),
          )
        ],
      ),
    );
  }
}
