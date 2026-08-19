import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Dart reducer matches every finite TLC oracle row',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'formal/tool/verify_oracle.dart'],
      );
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(
        '${result.stdout}',
        contains('Verified 99800 Dart transitions'),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
