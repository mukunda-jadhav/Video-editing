import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z-]+$').hasMatch(name) ||
          bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        return false;
      }
      final output = await Directory(
        'docs/screenshots',
      ).create(recursive: true);
      await File(
        '${output.path}/phase10-$name.png',
      ).writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: null,
  );
}
