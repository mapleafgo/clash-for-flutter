import 'package:flutter/material.dart';

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const SysAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: true,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}