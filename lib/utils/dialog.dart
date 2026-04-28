import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showErrorDialog(BuildContext context, String message) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('错误'),
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message));
            Navigator.pop(ctx);
          },
          child: const Text('复制'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
