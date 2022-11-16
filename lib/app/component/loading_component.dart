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
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: const BorderRadius.all(Radius.circular(5)),
                ),
                child: const CircularProgressIndicator(),
              ),
            ),
          ),
        );
      },
    );
  }
}
