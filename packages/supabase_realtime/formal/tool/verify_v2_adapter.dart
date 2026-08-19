import 'dart:convert';
import 'dart:io';

import 'package:supabase_realtime/src/kernel/realtime_v2_13_adapter.dart';

Future<void> main() async {
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final repositoryRoot = packageRoot.parent.parent;
  final manifest =
      (jsonDecode(
                File(
                  '${packageRoot.path}/formal/v2_13_adapter.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final pin = manifest['implementationPin']! as String;
  if (pin != RealtimeV213Adapter.implementationPin) {
    throw StateError('Dart and formal v2 adapter pins differ');
  }
  final object = await Process.run(
    'git',
    ['cat-file', '-t', pin],
    workingDirectory: repositoryRoot.path,
  );
  if (object.exitCode != 0 || '${object.stdout}'.trim() != 'commit') {
    throw StateError('Pinned v2 commit is unavailable: $pin');
  }

  final files = (manifest['files']! as Map).cast<String, Object?>();
  var clauses = 0;
  for (final entry in files.entries) {
    final show = await Process.run(
      'git',
      ['show', '$pin:${entry.key}'],
      workingDirectory: repositoryRoot.path,
    );
    if (show.exitCode != 0) {
      throw StateError('Pinned v2 source is missing ${entry.key}');
    }
    final source = '${show.stdout}';
    for (final token in (entry.value! as List<Object?>).cast<String>()) {
      clauses++;
      if (!source.contains(token)) {
        throw StateError(
          '${entry.key} no longer supplies adapter token $token',
        );
      }
    }
  }
  stdout.writeln(
    'Verified $clauses v2.13 adapter clauses against $pin.',
  );
}
