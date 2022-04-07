import 'package:clash_for_flutter/app/component/drawer_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class IndexPage extends StatefulWidget {
  @override
  _IndexPageState createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> {
  final PageController _page = PageController();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      AppDrawer(page: _page),
      Expanded(
        child: PageView.builder(
          controller: _page,
          itemCount: 3,
          itemBuilder: (cxt, i) {
            switch (i) {
              case 0:
                Modular.to.navigate("/tab/home");
                break;
              case 1:
                Modular.to.navigate("/tab/proxys");
                break;
              case 2:
                Modular.to.navigate("/tab/profiles");
                break;
            }
            return RouterOutlet();
          },
        ),
      )
    ]);
  }
}
