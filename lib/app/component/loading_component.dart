import 'package:flutter/material.dart';

class Loading {
  static OverlayEntry builder() {
    return OverlayEntry(
      builder: (_) {
        return Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0),
            ),
            child: Center(
              child: Container(
                child: CircularProgressIndicator(),
                padding: EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.all(Radius.circular(5)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
