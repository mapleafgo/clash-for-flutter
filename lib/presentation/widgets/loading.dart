import 'package:flutter/material.dart';

class Loading {
  final OverlayEntry _entry;
  Loading._() : _entry = OverlayEntry(
    builder: (_) => ColoredBox(
      color: const Color(0x66000000),
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  factory Loading.show(BuildContext context) {
    final loading = Loading._();
    Overlay.of(context).insert(loading._entry);
    return loading;
  }

  void remove() => _entry.remove();
}