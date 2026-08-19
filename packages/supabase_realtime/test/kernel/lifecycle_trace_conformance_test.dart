import 'dart:convert';
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

  test(
    'replay rejects a runtime transition that diverges from the model',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'realtime_mutated_trace_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final trace = '${directory.path}/trace.ndjson';
      final generate = await Process.run(Platform.resolvedExecutable, [
        'run',
        'formal/tool/generate_sample_trace.dart',
        trace,
      ]);
      expect(
        generate.exitCode,
        0,
        reason: '${generate.stdout}\n${generate.stderr}',
      );

      final file = File(trace);
      final entries = file.readAsLinesSync();
      final middle = (jsonDecode(entries[2]) as Map).cast<String, Object?>()
        ..['action'] = 'timeoutHeartbeat';
      entries[2] = jsonEncode(middle);
      file.writeAsStringSync('${entries.join('\n')}\n');

      final validate = await Process.run(Platform.resolvedExecutable, [
        'run',
        'formal/tool/validate_trace.dart',
        trace,
      ]);
      expect(
        validate.exitCode,
        isNot(0),
        reason: 'TLC accepted a transition with the wrong action',
      );
      expect(
        '${validate.stdout}${validate.stderr}',
        contains('TLC trace validation failed'),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
