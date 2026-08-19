import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'sample traces for every lifecycle machine replay through TLC',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'realtime_lifecycle_trace_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final trace = '${directory.path}/trace.ndjson';
      for (final command in [
        ['run', 'formal/tool/generate_sample_trace.dart', trace],
        ['run', 'formal/tool/validate_trace.dart', trace],
      ]) {
        final result = await Process.run(Platform.resolvedExecutable, command);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
