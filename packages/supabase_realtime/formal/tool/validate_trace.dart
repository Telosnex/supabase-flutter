import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';

import 'formal_hashes.dart';
import 'tla_value.dart';

const _tlaToolsSha256 =
    'ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final repositoryRoot = packageRoot.parent.parent;
  final formal = Directory('${packageRoot.path}/formal');
  final jar = File(
    options.jar ?? '${repositoryRoot.path}/.dart_tool/tla/tla2tools-1.8.0.jar',
  );
  final jarHash = sha256.convert(jar.readAsBytesSync()).toString();
  if (jarHash != _tlaToolsSha256) {
    throw StateError('Wrong tla2tools.jar SHA-256: $jarHash');
  }

  final manifest = _map(
    jsonDecode(File('${formal.path}/manifest.json').readAsStringSync()),
  );
  final requiredFields = (manifest['trace']! as Map)['requiredFields']! as List;
  final eventShapes = <String, Map<String, Map<String, String>>>{
    'socket': _shapes(manifest['events']),
    'channel': _shapes(manifest['channelEvents']),
    'push': _shapes(manifest['pushEvents']),
  };
  final effectShapes = <String, Map<String, Map<String, String>>>{
    'socket': _shapes(manifest['effects']),
    'channel': _shapes(manifest['channelEffects']),
    'push': _shapes(manifest['pushEffects']),
  };
  final expectedManifestHash = manifestSha256(packageRoot);
  final expectedModelHash = modelSha256(packageRoot);
  final lines = File(options.trace).readAsLinesSync()
    ..removeWhere((line) => line.trim().isEmpty);
  if (lines.isEmpty) throw StateError('Trace is empty');

  final groups = <String, List<Map<String, Object?>>>{};
  for (var index = 0; index < lines.length; index++) {
    final compact = _map(jsonDecode(lines[index]));
    for (final field in requiredFields) {
      if (!compact.containsKey(field)) {
        throw StateError('Trace entry ${index + 1} is missing $field');
      }
    }
    if (compact['schemaHash'] != expectedManifestHash ||
        compact['schemaHash'] != realtimeFormalManifestSha256) {
      throw StateError('Trace entry ${index + 1} has a stale schema hash');
    }
    if (compact['modelHash'] != expectedModelHash) {
      throw StateError('Trace entry ${index + 1} has a stale model hash');
    }
    final machine = compact['machine'];
    final instance = compact['instance'];
    if (machine is! String ||
        !eventShapes.containsKey(machine) ||
        instance is! String) {
      throw StateError('Trace entry ${index + 1} has an invalid machine');
    }
    final event = _map(compact['event']);
    final eventKind = event['kind']! as String;
    final eventShape = eventShapes[machine]![eventKind];
    if (eventShape == null) {
      throw StateError('Unknown $machine event $eventKind');
    }
    final expandedEffects = <Object?>[];
    for (final compactEffect in compact['effects']! as List<Object?>) {
      final effect = _map(compactEffect);
      final effectKind = effect['kind']! as String;
      final effectShape = effectShapes[machine]![effectKind];
      if (effectShape == null) {
        throw StateError('Unknown $machine effect $effectKind');
      }
      expandedEffects.add(_expandEffect(machine, effect));
    }
    groups.putIfAbsent('$machine\u0000$instance', () => []).add({
      ...compact,
      'event': _expandEvent(machine, event),
      'effects': expandedEffects,
    });
  }

  final root = Directory(
    '${repositoryRoot.path}/.dart_tool/realtime_formal/trace_validation',
  );
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);
  var validated = 0;
  for (final groupEntry in groups.entries) {
    final entries = groupEntry.value;
    entries.sort(
      (left, right) =>
          (left['sequence']! as int).compareTo(right['sequence']! as int),
    );
    for (var index = 0; index < entries.length; index++) {
      if (entries[index]['sequence'] != index + 1) {
        throw StateError(
          'Trace ${groupEntry.key} sequence is not contiguous at ${index + 1}',
        );
      }
    }
    final directory = Directory(
      '${root.path}/group_${groups.keys.toList().indexOf(groupEntry.key)}',
    )..createSync(recursive: true);
    await _validateGroup(
      entries: entries,
      directory: directory,
      formal: formal,
      jar: jar,
      expectedModelHash: expectedModelHash,
    );
    validated += entries.length;
  }
  stdout.writeln(
    'TLC validated $validated runtime trace entries across '
    '${groups.length} machine instances.',
  );
}

Future<void> _validateGroup({
  required List<Map<String, Object?>> entries,
  required Directory directory,
  required Directory formal,
  required File jar,
  required String expectedModelHash,
}) async {
  final loadedTrace = {
    'counterexample': {
      'state': [
        for (var index = 0; index < entries.length; index++)
          [
            index + 1,
            {'entry': entries[index]},
          ],
      ],
    },
    'vars': ['entry'],
  };
  File('${directory.path}/trace.json').writeAsStringSync(
    jsonEncode(loadedTrace),
  );
  File('${directory.path}/TraceEntries.tla').writeAsStringSync(
    '----------------------- MODULE TraceEntries -----------------------\n'
    'TraceEntries == {\n'
    '${entries.map(encodeTlaValue).join(',\n')}\n'
    '}\n'
    '===================================================================\n',
  );

  final bounds = _traceBounds(entries);
  File('${directory.path}/LifecycleTraceValidation.cfg').writeAsStringSync('''
SPECIFICATION Spec
CHECK_DEADLOCK FALSE

CONSTANTS
    MaxGeneration            = ${bounds.maxGeneration}
    MaxTimerId               = ${bounds.maxTimerId}
    MaxHeartbeatRef          = ${bounds.maxHeartbeatRef}
    MaxRetryCount            = ${bounds.maxRetryCount}
    MaxChannelId             = ${bounds.maxChannelId}
    MaxJoinEpoch             = ${bounds.maxJoinEpoch}
    MaxPushRef               = ${bounds.maxPushRef}
    MaxChannelPushTimerId    = ${bounds.maxTimerId}
    ExpectedModelHash        = "$expectedModelHash"

INVARIANT TraceEntryOK
''');

  final separator = Platform.isWindows ? ';' : ':';
  final libraryPath = [
    directory.absolute.path,
    Directory('${formal.path}/generated').absolute.path,
    formal.absolute.path,
  ].join(separator);
  final result = await Process.run(
    'java',
    [
      '-DTLA-Library=$libraryPath',
      '-XX:+UseParallelGC',
      '-cp',
      jar.absolute.path,
      'tlc2.TLC',
      'LifecycleTraceValidation',
      '-config',
      'LifecycleTraceValidation.cfg',
      '-loadTrace',
      'json',
      'trace.json',
      '-workers',
      '1',
      '-seed',
      '1',
      '-fp',
      '0',
      '-metadir',
      '${directory.path}/states',
      '-cleanup',
    ],
    workingDirectory: directory.path,
  ).timeout(const Duration(seconds: 30));
  final output = '${result.stdout}${result.stderr}';
  if (result.exitCode != 0 ||
      !output.contains('Model checking completed. No error has been found.')) {
    throw StateError('TLC trace validation failed:\n$output');
  }
}

Map<String, Object?> _expandEvent(
  String machine,
  Map<String, Object?> compact,
) => switch (machine) {
  'socket' => {
    'kind': compact['kind'],
    'generation': compact['generation'] ?? 0,
    'timerId': compact['timerId'] ?? 0,
    'ref': compact['ref'] ?? 0,
    'failureKind': compact['failureKind'] ?? 'none',
    'heartbeatStatus': compact['heartbeatStatus'] ?? 'none',
    'grace': compact['grace'] ?? 'none',
  },
  'channel' => {
    'kind': compact['kind'],
    'available': compact['available'] ?? false,
    'epoch': compact['epoch'] ?? 0,
    'replyStatus': compact['replyStatus'] ?? 'none',
    'timerId': compact['timerId'] ?? 0,
  },
  'push' => {
    'kind': compact['kind'],
    'ref': compact['ref'] ?? 0,
    'replyStatus': compact['replyStatus'] ?? 'none',
    'timerId': compact['timerId'] ?? 0,
  },
  _ => throw StateError('Unknown machine $machine'),
};

Map<String, Object?> _expandEffect(
  String machine,
  Map<String, Object?> compact,
) => switch (machine) {
  'socket' => {
    'kind': compact['kind'],
    'generation': compact['generation'] ?? 0,
    'timerId': compact['timerId'] ?? 0,
    'ref': compact['ref'] ?? 0,
    'delayOrdinal': compact['delayOrdinal'] ?? 0,
    'failureKind': compact['failureKind'] ?? 'none',
    'heartbeatStatus': compact['heartbeatStatus'] ?? 'none',
    'tokenMode': compact['tokenMode'] ?? 'none',
    'closeReason': compact['closeReason'] ?? 'none',
  },
  'channel' => {
    'kind': compact['kind'],
    'epoch': compact['epoch'] ?? 0,
    'timerId': compact['timerId'] ?? 0,
    'requesterChannelId': compact['requesterChannelId'] ?? 0,
    'replyStatus': compact['replyStatus'] ?? 'none',
  },
  'push' => {
    'kind': compact['kind'],
    'ref': compact['ref'] ?? 0,
    'replyStatus': compact['replyStatus'] ?? 'none',
    'timerId': compact['timerId'] ?? 0,
  },
  _ => throw StateError('Unknown machine $machine'),
};

_Bounds _traceBounds(List<Map<String, Object?>> entries) {
  var generation = 1;
  var timerId = 1;
  var heartbeatRef = 1;
  var retryCount = 1;
  var channelId = 1;
  var joinEpoch = 1;
  var pushRef = 1;

  void visit(Object? value, [String? key]) {
    if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, '${entry.key}');
      }
    } else if (value is List) {
      for (final item in value) {
        visit(item, key);
      }
    } else if (value is int) {
      switch (key) {
        case 'generation' || 'activeGeneration':
          generation = _max(generation, value);
        case 'nextGeneration':
          generation = _max(generation, value - 1);
        case 'timerId' || 'id':
          timerId = _max(timerId, value);
        case 'nextTimerId':
          timerId = _max(timerId, value - 1);
        case 'ref':
          heartbeatRef = _max(heartbeatRef, value);
          pushRef = _max(pushRef, value);
        case 'nextHeartbeatRef':
          heartbeatRef = _max(heartbeatRef, value - 1);
        case 'retryCount':
          retryCount = _max(retryCount, value + 1);
        case 'channelId' || 'requesterChannelId':
          channelId = _max(channelId, value);
        case 'epoch' || 'activeJoinEpoch':
          joinEpoch = _max(joinEpoch, value);
        case 'nextJoinEpoch':
          joinEpoch = _max(joinEpoch, value - 1);
        case 'activeRef':
          pushRef = _max(pushRef, value);
        case 'nextRef':
          pushRef = _max(pushRef, value - 1);
      }
    }
  }

  for (final entry in entries) {
    visit(entry);
  }
  return _Bounds(
    maxGeneration: generation,
    maxTimerId: timerId,
    maxHeartbeatRef: heartbeatRef,
    maxRetryCount: retryCount,
    maxChannelId: channelId,
    maxJoinEpoch: joinEpoch,
    maxPushRef: pushRef,
  );
}

int _max(int left, int right) => right > left ? right : left;

Map<String, Map<String, String>> _shapes(Object? value) => _map(value).map(
  (key, fields) => MapEntry(key, _map(fields).cast<String, String>()),
);

Map<String, Object?> _map(Object? value) =>
    (value! as Map).cast<String, Object?>();

final class _Bounds {
  const _Bounds({
    required this.maxGeneration,
    required this.maxTimerId,
    required this.maxHeartbeatRef,
    required this.maxRetryCount,
    required this.maxChannelId,
    required this.maxJoinEpoch,
    required this.maxPushRef,
  });

  final int maxGeneration;
  final int maxTimerId;
  final int maxHeartbeatRef;
  final int maxRetryCount;
  final int maxChannelId;
  final int maxJoinEpoch;
  final int maxPushRef;
}

final class _Options {
  const _Options({required this.trace, required this.jar});

  factory _Options.parse(List<String> arguments) {
    String? trace;
    String? jar;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--jar':
          jar = arguments[++index];
        default:
          if (trace != null) throw const FormatException('Too many paths');
          trace = arguments[index];
      }
    }
    if (trace == null) {
      throw const FormatException(
        'Usage: validate_trace.dart [--jar JAR] TRACE',
      );
    }
    return _Options(trace: trace, jar: jar);
  }

  final String trace;
  final String? jar;
}
