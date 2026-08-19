import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final repositoryRoot = packageRoot.parent.parent;
  final manifest =
      (jsonDecode(
                File(
                  '${packageRoot.path}/formal/mutants/dart/manifest.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final worktree = Directory.systemTemp.createTempSync(
    'supabase_realtime_mutants_',
  );
  worktree.deleteSync(recursive: true);

  try {
    await _requireSuccess(
      'git',
      ['worktree', 'add', '--detach', worktree.path, 'HEAD'],
      workingDirectory: repositoryRoot,
    );
    final targetPackage = Directory(
      '${worktree.path}/packages/supabase_realtime',
    );
    final targetTool = Directory('${worktree.path}/.dart_tool')
      ..createSync(recursive: true);
    File('${repositoryRoot.path}/.dart_tool/package_config.json').copySync(
      '${targetTool.path}/package_config.json',
    );

    for (final entry in manifest.entries) {
      final definition = (entry.value! as Map).cast<String, Object?>();
      await _syncPackage(packageRoot, targetPackage);
      final patch = File(
        '${packageRoot.path}/formal/mutants/dart/${definition['patch']}',
      );
      await _requireSuccess(
        'git',
        [
          'apply',
          '--directory=packages/supabase_realtime',
          patch.path,
        ],
        workingDirectory: worktree,
      );

      final detector = definition['detector']! as String;
      final command = switch (detector) {
        'socketOracle' => [
          'run',
          'formal/tool/verify_oracle.dart',
        ],
        'channelPushOracle' => [
          'run',
          'formal/tool/verify_channel_push_oracle.dart',
          '--channel-dump',
          options.channelDump,
          '--push-dump',
          options.pushDump,
          '--reachable-dump',
          options.reachableDump,
        ],
        'property' when entry.key == 'D03_NullPayloadCrash' => [
          'test',
          'test/transformers_test.dart',
          '-n',
          'getPayloadRecords resilience',
        ],
        'property' => [
          'test',
          'test/realtime_presence_test.dart',
        ],
        _ => throw StateError('Unknown detector $detector'),
      };
      final result = await _run(
        Platform.resolvedExecutable,
        command,
        workingDirectory: targetPackage,
      );
      if (result.exitCode == 0) {
        throw StateError(
          '${entry.key} survived its $detector detector:\n${result.output}',
        );
      }
      stdout.writeln('${entry.key}: caught by $detector');
    }
    stdout.writeln('Dart mutation audit caught ${manifest.length} mutants.');
  } finally {
    if (worktree.existsSync()) {
      await _run(
        'git',
        ['worktree', 'remove', '--force', worktree.path],
        workingDirectory: repositoryRoot,
      );
    }
  }
}

Future<void> _syncPackage(Directory source, Directory target) async {
  await _requireSuccess(
    'rsync',
    [
      '-a',
      '--delete',
      '--exclude=.dart_tool',
      '${source.path}/',
      '${target.path}/',
    ],
    workingDirectory: source,
  );
}

Future<void> _requireSuccess(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) async {
  final result = await _run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed:\n${result.output}',
    );
  }
}

Future<_Result> _run(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  ).timeout(const Duration(minutes: 2));
  return _Result(
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}',
  );
}

final class _Result {
  const _Result({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

final class _Options {
  const _Options({
    required this.channelDump,
    required this.pushDump,
    required this.reachableDump,
  });

  factory _Options.parse(List<String> arguments) {
    String? channelDump;
    String? pushDump;
    String? reachableDump;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--channel-dump':
          channelDump = File(arguments[++index]).absolute.path;
        case '--push-dump':
          pushDump = File(arguments[++index]).absolute.path;
        case '--reachable-dump':
          reachableDump = File(arguments[++index]).absolute.path;
        default:
          throw FormatException('Unknown argument ${arguments[index]}');
      }
    }
    if (channelDump == null || pushDump == null || reachableDump == null) {
      throw const FormatException(
        '--channel-dump, --push-dump, and --reachable-dump are required',
      );
    }
    return _Options(
      channelDump: channelDump,
      pushDump: pushDump,
      reachableDump: reachableDump,
    );
  }

  final String channelDump;
  final String pushDump;
  final String reachableDump;
}
