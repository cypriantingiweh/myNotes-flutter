import 'package:flutter/material.dart';

Future<void> showErrorDialog(BuildContext buildContext, String text) {
  return showDialog(
      context: buildContext,
      builder: (context) {
        return AlertDialog(
          title: const Text('An error occur'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Ok'),
            )
          ],
        );
      });
}
