import 'package:flutter/material.dart';

class Loading {
  static OverlayEntry builder() {
    return OverlayEntry(
      builder: (_) {
        return Center(
          child: Card(
            child: Container(
              child: CircularProgressIndicator(),
              padding: EdgeInsets.all(30),
            ),
          ),
        );
      },
    );
  }
}
