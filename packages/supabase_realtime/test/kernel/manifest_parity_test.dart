import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated TLA+ and Dart lifecycle schemas are current', () async {
    for (final command in [
      ['run', 'formal/tool/generate_schema.dart', '--check'],
      ['run', 'formal/tool/generate_model_hash.dart', '--check'],
    ]) {
      final result = await Process.run(Platform.resolvedExecutable, command);
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
    }
  });
}
