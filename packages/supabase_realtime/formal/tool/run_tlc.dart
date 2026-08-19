import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'tla_value.dart';

const _tlaToolsSha256 =
    'ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f';
const _timeout = Duration(minutes: 2);
const _mutants = <String, String>{
  'M01_KeepPushTimeoutOnResend': 'P1_SentPushOwnsRefAndTimer',
  'M02_BypassTokenProvider': 'S6_HeartbeatRefreshesTokenSource',
  'M05_CarryHeartbeatDebt': 'S4_HeartbeatOwnedByGeneration',
  'M06_WedgeConnectingOnSyncThrow': 'S3_PhaseOwnsTransport',
  'M07_LeaveRejectedJoinJoining': 'C1_JoinFailureSchedulesRejoin',
  'M08_SelfRearmRejoinTimer': 'C2_RejoinTimerOwned',
  'M09_EvictRejoiningChannel': 'C3_DuplicateEvictionExcludesRequester',
  'M10_NoRetryOnSyncThrow': 'S2_FailureSchedulesRecovery',
  'M11_KeepRetryAfterDisconnect': 'S1_NoWorkAgainstDownIntent',
  'M12_ResetRetryDuringRecovery': 'S5_BackoffOrdinal',
};

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final repositoryRoot = packageRoot.parent.parent;
  final formal = Directory('${packageRoot.path}/formal');
  final output = Directory(
    '${repositoryRoot.path}/.dart_tool/realtime_formal/gate',
  );
  if (output.existsSync()) output.deleteSync(recursive: true);
  output.createSync(recursive: true);

  final jar = File(
    options.jar ?? '${repositoryRoot.path}/.dart_tool/tla/tla2tools-1.8.0.jar',
  );
  _verifyJar(jar);
  await _checkJava();
  await _runDart(
    packageRoot,
    ['run', 'formal/tool/generate_schema.dart', '--check'],
  );
  await _runDart(
    packageRoot,
    ['run', 'formal/tool/generate_model_hash.dart', '--check'],
  );

  final report = <String, Object?>{
    'tlaToolsSha256': _tlaToolsSha256,
    'workerCount': 1,
    'seed': 1,
    'fingerprintIndex': 0,
  };

  stdout.writeln('\n=== Pristine safety model ===');
  final safetyDirectory = Directory('${output.path}/safety')
    ..createSync(recursive: true);
  final reachableDump = File('${safetyDirectory.path}/reachable.dump');
  final safety = await _runTlc(
    jar: jar,
    module: 'RealtimeSocket',
    config: 'SocketSafety.cfg',
    workingDirectory: formal,
    metadataDirectory: Directory('${safetyDirectory.path}/states'),
    libraryDirectories: [Directory('${formal.path}/generated')],
    dump: reachableDump,
    streamOutput: true,
  );
  _requireSuccess('pristine safety model', safety);
  report['safety'] = _metrics(safety.output);

  final reachableAssignments = parseTlcDump(
    reachableDump.readAsStringSync(),
  ).toList(growable: false);
  final protocolStates = <String, Object?>{};
  var scopeExhausted = 0;
  for (final assignment in reachableAssignments) {
    if (assignment['scopeExhausted']! as bool) {
      scopeExhausted++;
      continue;
    }
    final state = assignment['state']!;
    protocolStates[jsonEncode(state)] = state;
  }
  stdout.writeln(
    'Boundary accounting: ${reachableAssignments.length} TLC states, '
    '${protocolStates.length} protocol states, '
    '$scopeExhausted ScopeExhausted states.',
  );
  (report['safety']! as Map<String, Object?>)
    ..['protocolStates'] = protocolStates.length
    ..['scopeExhaustedStates'] = scopeExhausted;

  stdout.writeln('\n=== Channel/push safety model ===');
  final channelPushDirectory = Directory('${output.path}/channel_push')
    ..createSync(recursive: true);
  final channelPushDump = File(
    '${channelPushDirectory.path}/reachable.dump',
  );
  final channelPushSafety = await _runTlc(
    jar: jar,
    module: 'RealtimeChannelPush',
    config: 'ChannelPushSafety.cfg',
    workingDirectory: formal,
    metadataDirectory: Directory('${channelPushDirectory.path}/states'),
    libraryDirectories: [Directory('${formal.path}/generated')],
    dump: channelPushDump,
    streamOutput: true,
  );
  _requireSuccess('channel/push safety model', channelPushSafety);
  report['channelPushSafety'] = _metrics(channelPushSafety.output);

  stdout.writeln('\n=== Historical lifecycle mutants ===');
  final mutantReports = <String, Object?>{};
  for (final entry in _mutants.entries) {
    stdout.write('${entry.key}: ');
    final mutantDirectory = Directory('${output.path}/mutants/${entry.key}')
      ..createSync(recursive: true);
    final run = await _runTlc(
      jar: jar,
      module: entry.key,
      config: '${entry.key}.cfg',
      workingDirectory: mutantDirectory,
      metadataDirectory: Directory('${mutantDirectory.path}/states'),
      libraryDirectories: [
        Directory('${formal.path}/mutants/tla'),
        Directory('${formal.path}/generated'),
        formal,
      ],
      streamOutput: false,
    );
    final violations = RegExp(
      r'Error: Invariant ([A-Za-z0-9_]+) is violated',
    ).allMatches(run.output).map((match) => match.group(1)!).toList();
    if (run.exitCode == 0 ||
        violations.length != 1 ||
        violations.single != entry.value) {
      stderr
        ..writeln('FAILED')
        ..writeln(run.output)
        ..writeln(
          'Expected only ${entry.value}; got ${violations.join(', ')} '
          '(exit ${run.exitCode}).',
        );
      exitCode = 1;
      return;
    }
    stdout.writeln('caught by ${entry.value}');
    mutantReports[entry.key] = {
      'expectedInvariant': entry.value,
      'exitCode': run.exitCode,
      ..._metricsOrEmpty(run.output),
    };
  }
  report['mutants'] = mutantReports;

  stdout.writeln('\n=== Complete channel/push transition oracles ===');
  final channelPushInput = Directory('${output.path}/channel_push_input');
  await _runDart(packageRoot, [
    'run',
    'formal/tool/generate_channel_push_reachable.dart',
    channelPushDump.path,
    channelPushInput.path,
  ]);
  final channelPushOracleMetrics = <String, Object?>{};
  final oracleDumps = <String, String>{};
  for (final module in ['ChannelOracle', 'PushOracle']) {
    final directory = Directory('${output.path}/$module')
      ..createSync(recursive: true);
    final dump = File('${directory.path}/oracle.dump');
    final run = await _runTlc(
      jar: jar,
      module: module,
      config: 'ChannelPushOracle.cfg',
      workingDirectory: formal,
      metadataDirectory: Directory('${directory.path}/states'),
      libraryDirectories: [
        Directory('${formal.path}/generated'),
        channelPushInput,
        formal,
      ],
      dump: dump,
      streamOutput: true,
    );
    _requireSuccess('$module transition oracle', run);
    channelPushOracleMetrics[module] = _metrics(run.output);
    oracleDumps[module] = dump.path;
  }
  final channelPushReport = File(
    '${output.path}/channel_push_oracle_report.json',
  );
  await _runDart(packageRoot, [
    'run',
    'formal/tool/verify_channel_push_oracle.dart',
    '--channel-dump',
    oracleDumps['ChannelOracle']!,
    '--push-dump',
    oracleDumps['PushOracle']!,
    '--reachable-dump',
    channelPushDump.path,
    '--report',
    channelPushReport.path,
  ]);
  report['channelPushOracles'] = {
    'tlc': channelPushOracleMetrics,
    'coverage': jsonDecode(channelPushReport.readAsStringSync()),
  };

  stdout.writeln('\n=== Complete TLC transition oracle ===');
  final oracleInput = Directory('${output.path}/oracle_input')
    ..createSync(recursive: true);
  final stateValues = protocolStates.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  File('${oracleInput.path}/ReachableStates.tla').writeAsStringSync(
    '---------------------- MODULE ReachableStates ----------------------\n'
    '\\* Generated from the pristine TLC state dump.\n\n'
    'ReachableStates == {\n'
    '${stateValues.map((entry) => encodeTlaValue(entry.value)).join(',\n')}\n'
    '}\n\n'
    '====================================================================\n',
  );
  final oracleDirectory = Directory('${output.path}/oracle')
    ..createSync(recursive: true);
  final oracleDump = File('${oracleDirectory.path}/oracle.dump');
  final oracle = await _runTlc(
    jar: jar,
    module: 'SocketOracle',
    config: 'SocketOracle.cfg',
    workingDirectory: formal,
    metadataDirectory: Directory('${oracleDirectory.path}/states'),
    libraryDirectories: [
      Directory('${formal.path}/generated'),
      oracleInput,
      formal,
    ],
    dump: oracleDump,
    streamOutput: true,
  );
  _requireSuccess('transition oracle', oracle);
  report['oracle'] = _metrics(oracle.output);

  final candidate = File('${output.path}/socket_transition_oracle.json.gz');
  await _runDart(packageRoot, [
    'run',
    'formal/tool/generate_oracle.dart',
    '--reachable-dump',
    reachableDump.path,
    '--oracle-dump',
    oracleDump.path,
    '--output',
    candidate.path,
  ]);
  final committed = File(
    '${formal.path}/oracle/socket_transition_oracle.json.gz',
  );
  if (options.updateOracle) {
    committed.parent.createSync(recursive: true);
    candidate.copySync(committed.path);
    stdout.writeln('Updated ${committed.path}.');
  } else if (!committed.existsSync() ||
      !_bytesEqual(candidate.readAsBytesSync(), committed.readAsBytesSync())) {
    stderr.writeln(
      'Committed transition oracle is stale. Run:\n'
      '  dart run formal/tool/run_tlc.dart --update-oracle',
    );
    exitCode = 1;
    return;
  }
  await _runDart(
    packageRoot,
    ['run', 'formal/tool/verify_oracle.dart', committed.path],
  );

  stdout.writeln('\n=== Accepted action trace coverage ===');
  final actionTrace = File('${output.path}/action_coverage_trace.ndjson');
  await _runDart(packageRoot, [
    'run',
    'formal/tool/generate_action_coverage_trace.dart',
    '--socket-oracle',
    committed.path,
    '--channel-dump',
    oracleDumps['ChannelOracle']!,
    '--push-dump',
    oracleDumps['PushOracle']!,
    '--reachable-dump',
    channelPushDump.path,
    '--output',
    actionTrace.path,
  ]);
  await _runDart(packageRoot, [
    'run',
    'formal/tool/validate_trace.dart',
    '--jar',
    jar.path,
    actionTrace.path,
  ]);
  report['acceptedActionsTraced'] = 52;

  stdout.writeln('\n=== Dart defect-reinjection audit ===');
  await _runDart(packageRoot, [
    'run',
    'formal/tool/audit_dart_mutants.dart',
    '--channel-dump',
    oracleDumps['ChannelOracle']!,
    '--push-dump',
    oracleDumps['PushOracle']!,
    '--reachable-dump',
    channelPushDump.path,
  ]);
  report['dartMutantsCaught'] = 12;

  stdout.writeln('\n=== Runtime trace replay ===');
  final sampleTrace = File('${output.path}/sample_trace.ndjson');
  await _runDart(packageRoot, [
    'run',
    'formal/tool/generate_sample_trace.dart',
    sampleTrace.path,
  ]);
  await _runDart(packageRoot, [
    'run',
    'formal/tool/validate_trace.dart',
    '--jar',
    jar.path,
    sampleTrace.path,
  ]);
  report['runtimeTraceEntries'] = sampleTrace.readAsLinesSync().length;

  stdout.writeln('\n=== Seeded randomized trace replay ===');
  final randomTrace = File('${output.path}/random_trace.ndjson');
  await _runDart(packageRoot, [
    'run',
    'formal/tool/generate_random_trace.dart',
    randomTrace.path,
  ]);
  await _runDart(packageRoot, [
    'run',
    'formal/tool/validate_trace.dart',
    '--jar',
    jar.path,
    randomTrace.path,
  ]);
  report['randomTraceEntries'] = randomTrace.readAsLinesSync().length;

  final reportFile = File('${output.path}/report.json');
  reportFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln('\nFormal gate passed. Report: ${reportFile.path}');
}

void _verifyJar(File jar) {
  if (!jar.existsSync()) {
    throw StateError(
      'Missing tla2tools.jar at ${jar.path}. Download TLA+ v1.8.0 or pass '
      '--jar PATH.',
    );
  }
  final actual = sha256.convert(jar.readAsBytesSync()).toString();
  if (actual != _tlaToolsSha256) {
    throw StateError(
      'Wrong tla2tools.jar SHA-256: $actual; expected $_tlaToolsSha256',
    );
  }
  stdout.writeln('Verified TLA+ tools: $_tlaToolsSha256');
}

Future<void> _checkJava() async {
  final result = await Process.run('java', ['-version']);
  if (result.exitCode != 0) {
    throw StateError('Java is unavailable:\n${result.stderr}');
  }
  final versionText = '${result.stdout}${result.stderr}';
  final match = RegExp(r'version "([0-9]+)').firstMatch(versionText);
  if (match == null || int.parse(match.group(1)!) < 21) {
    throw StateError('Java 21 or newer is required:\n$versionText');
  }
}

Future<_ProcessResult> _runTlc({
  required File jar,
  required String module,
  required String config,
  required Directory workingDirectory,
  required Directory metadataDirectory,
  required List<Directory> libraryDirectories,
  required bool streamOutput,
  File? dump,
}) {
  metadataDirectory.createSync(recursive: true);
  final separator = Platform.isWindows ? ';' : ':';
  final libraryPath = libraryDirectories
      .map((path) => path.absolute.path)
      .join(separator);
  final arguments = <String>[
    '-DTLA-Library=$libraryPath',
    '-XX:+UseParallelGC',
    '-cp',
    jar.absolute.path,
    'tlc2.TLC',
    module,
    '-config',
    config,
    '-workers',
    '1',
    '-seed',
    '1',
    '-fp',
    '0',
    '-metadir',
    metadataDirectory.absolute.path,
    if (dump != null) ...['-dump', dump.absolute.path],
    '-cleanup',
  ];
  return _runProcess(
    'java',
    arguments,
    workingDirectory: workingDirectory,
    streamOutput: streamOutput,
  );
}

Future<void> _runDart(Directory packageRoot, List<String> arguments) async {
  final result = await _runProcess(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: packageRoot,
    streamOutput: true,
  );
  if (result.exitCode != 0) {
    throw StateError('Dart command failed (${result.exitCode})');
  }
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
  required bool streamOutput,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  final output = StringBuffer();
  final drains = <Future<void>>[];
  void listen(Stream<List<int>> stream) {
    drains.add(
      stream.transform(utf8.decoder).forEach((chunk) {
        output.write(chunk);
        if (streamOutput) stdout.write(chunk);
      }),
    );
  }

  listen(process.stdout);
  listen(process.stderr);
  int exit;
  try {
    exit = await process.exitCode.timeout(_timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    throw TimeoutException(
      '$executable ${arguments.join(' ')} exceeded $_timeout',
    );
  }
  await Future.wait(drains);
  return _ProcessResult(exitCode: exit, output: output.toString());
}

void _requireSuccess(String name, _ProcessResult result) {
  if (result.exitCode != 0 ||
      !result.output.contains(
        'Model checking completed. No error has been found.',
      )) {
    throw StateError('$name failed (${result.exitCode})\n${result.output}');
  }
}

Map<String, Object?> _metrics(String output) {
  final stateMatch = RegExp(
    r'([0-9,]+) states generated, ([0-9,]+) distinct states found, '
    r'([0-9,]+) states left on queue',
  ).allMatches(output).lastOrNull;
  final depthMatch = RegExp(
    r'The depth of the complete state graph search is ([0-9,]+)',
  ).firstMatch(output);
  if (stateMatch == null || depthMatch == null) {
    throw StateError('TLC output did not contain complete state metrics');
  }
  int parse(String value) => int.parse(value.replaceAll(',', ''));
  return {
    'generatedStates': parse(stateMatch.group(1)!),
    'distinctStates': parse(stateMatch.group(2)!),
    'statesLeftOnQueue': parse(stateMatch.group(3)!),
    'searchDepth': parse(depthMatch.group(1)!),
  };
}

Map<String, Object?> _metricsOrEmpty(String output) {
  try {
    return _metrics(output);
  } on StateError {
    return const {};
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _ProcessResult {
  const _ProcessResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

final class _Options {
  const _Options({required this.jar, required this.updateOracle});

  factory _Options.parse(List<String> arguments) {
    String? jar;
    var updateOracle = false;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--jar':
          if (++index == arguments.length) {
            throw const FormatException('--jar requires a path');
          }
          jar = arguments[index];
        case '--update-oracle':
          updateOracle = true;
        default:
          throw FormatException('Unknown argument: ${arguments[index]}');
      }
    }
    return _Options(jar: jar, updateOracle: updateOracle);
  }

  final String? jar;
  final bool updateOracle;
}

extension<T> on Iterable<T> {
  T? get lastOrNull {
    T? result;
    for (final value in this) {
      result = value;
    }
    return result;
  }
}
