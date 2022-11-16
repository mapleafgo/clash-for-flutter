import 'package:asuka/asuka.dart';
import 'package:flutter/material.dart' hide MenuItem;
import 'package:flutter_modular/flutter_modular.dart';

class AppWidget extends StatefulWidget {
  const AppWidget({super.key});

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  @override
  Widget build(BuildContext context) {
    var app = MaterialApp.router(
      title: "Clash For Flutter",
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
      ),
      routeInformationParser: Modular.routeInformationParser,
      routerDelegate: Modular.routerDelegate,
      builder: Asuka.builder,
      // navigatorObservers: [Asuka.asukaHeroController],
    );
    Modular.setObservers([Asuka.asukaHeroController]);
    return app;
  }
}
