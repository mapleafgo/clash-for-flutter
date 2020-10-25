import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:asuka/asuka.dart' as asuka;

class AppWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
        initialRoute: "/",
        builder: asuka.builder,
        navigatorKey: Modular.navigatorKey,
        onGenerateRoute: Modular.generateRoute,
      );
}
