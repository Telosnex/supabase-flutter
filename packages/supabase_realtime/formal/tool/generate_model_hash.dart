import 'dart:io';

import 'formal_hashes.dart';

void main(List<String> arguments) {
  final check = arguments.contains('--check');
  if (arguments.any((argument) => argument != '--check')) {
    throw const FormatException('Only --check is supported');
  }
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final hash = modelSha256(packageRoot);
  final content =
      '''// GENERATED FILE. DO NOT EDIT.
// Hashes the reviewed TLA+ model and deterministic configurations.

const realtimeSocketModelSha256 =
    '$hash';
''';
  final output = File(
    '${packageRoot.path}/lib/src/kernel/generated/model_hash.dart',
  );
  if (check) {
    if (!output.existsSync() || output.readAsStringSync() != content) {
      stderr.writeln('Generated model hash is stale: ${output.path}');
      exitCode = 1;
    }
    return;
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(content);
  stdout.writeln('Generated ${output.path}');
}
