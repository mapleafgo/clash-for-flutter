import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:singcast/i18n/strings.g.dart';

Future<void> showErrorDialog(BuildContext context, String message) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.dialogs.error),
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message));
            Navigator.pop(ctx);
          },
          child: Text(t.dialogs.copy),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.dialogs.confirm),
        ),
      ],
    ),
  );
}
