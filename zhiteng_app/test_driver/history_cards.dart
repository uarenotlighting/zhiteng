import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('../artifacts/history-cards');
  await output.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? const {});
      report.remove('screenshots');
      await File(
        '${output.path}/report.json',
      ).writeAsString(const JsonEncoder.withIndent(' ').convert(report));
    },
  );
}
