import 'dart:convert';
import 'dart:io';

import 'formal_hashes.dart';
import 'tla_value.dart';

const _formatVersion = 1;

void main(List<String> arguments) {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final manifestFile = File('${packageRoot.path}/formal/manifest.json');
  final manifestBytes = manifestFile.readAsBytesSync();
  final manifest = (jsonDecode(utf8.decode(manifestBytes)) as Map)
      .cast<String, Object?>();
  final records = _shapes(manifest['records']);
  final events = _shapes(manifest['events']);
  final effects = _shapes(manifest['effects']);

  stdout.writeln('Parsing reachable-state dump...');
  final reachableAssignments = parseTlcDump(
    File(options.reachableDump).readAsStringSync(),
  );
  final protocolStateByKey = <String, Map<String, Object?>>{};
  var tlcStateCount = 0;
  var scopeExhaustedStateCount = 0;
  for (final assignment in reachableAssignments) {
    tlcStateCount++;
    final scopeExhausted = assignment['scopeExhausted']! as bool;
    if (scopeExhausted) {
      scopeExhaustedStateCount++;
      continue;
    }
    final state = _normalizeRecord(
      _map(assignment['state']),
      records['SocketModelState']!,
      records,
    );
    protocolStateByKey[_canonical(state)] = state;
  }

  stdout.writeln('Parsing transition-oracle dump...');
  final rowByPair = <String, _ParsedRow>{};
  final preStateKeys = <String>{};
  final eventByKey = <String, Map<String, Object?>>{};
  final effectListByKey = <String, List<Object?>>{};
  final actionCounts = <String, int>{};
  final dispositionCounts = <String, int>{};
  var parsedRows = 0;
  for (final assignment in parseTlcDump(
    File(options.oracleDump).readAsStringSync(),
  )) {
    parsedRows++;
    final preState = _normalizeRecord(
      _map(assignment['preState']),
      records['SocketModelState']!,
      records,
    );
    final preKey = _canonical(preState);
    if (!protocolStateByKey.containsKey(preKey)) {
      throw StateError('Oracle pre-state is absent from reachable states');
    }
    preStateKeys.add(preKey);

    final fullEvent = _map(assignment['event']);
    final eventKind = fullEvent['kind']! as String;
    final eventShape = events[eventKind];
    if (eventShape == null) throw StateError('Unknown event kind $eventKind');
    final event = <String, Object?>{
      'kind': eventKind,
      ..._normalizeRecord(fullEvent, eventShape, records),
    };
    final eventKey = _canonical(event);
    eventByKey[eventKey] = event;

    final result = _map(assignment['result']);
    final postState = _normalizeRecord(
      _map(result['postState']),
      records['SocketModelState']!,
      records,
    );
    final postKey = _canonical(postState);
    if (!protocolStateByKey.containsKey(postKey)) {
      throw StateError('Oracle post-state is absent from reachable states');
    }

    final compactEffects = <Object?>[];
    for (final rawEffect in (result['effects']! as List<Object?>)) {
      final fullEffect = _map(rawEffect);
      final effectKind = fullEffect['kind']! as String;
      final effectShape = effects[effectKind];
      if (effectShape == null) {
        throw StateError('Unknown effect kind $effectKind');
      }
      compactEffects.add({
        'kind': effectKind,
        ..._normalizeRecord(fullEffect, effectShape, records),
      });
    }
    final effectListKey = _canonical(compactEffects);
    effectListByKey[effectListKey] = compactEffects;

    final disposition = result['disposition']! as String;
    final action = result['action']! as String;
    actionCounts.update(action, (count) => count + 1, ifAbsent: () => 1);
    dispositionCounts.update(
      disposition,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    final pairKey = '$preKey\u0000$eventKey';
    if (rowByPair.containsKey(pairKey)) {
      throw StateError('TLC emitted two results for one state/event pair');
    }
    rowByPair[pairKey] = _ParsedRow(
      disposition: disposition,
      action: action,
      postStateKey: postKey,
      effectListKey: effectListKey,
    );
  }

  final stateKeys = protocolStateByKey.keys.toList()..sort();
  final sortedPreStateKeys = preStateKeys.toList()..sort();
  final eventKeys = eventByKey.keys.toList()..sort();
  final effectListKeys = effectListByKey.keys.toList()..sort();
  final expectedRows = sortedPreStateKeys.length * eventKeys.length;
  if (parsedRows != expectedRows || rowByPair.length != expectedRows) {
    throw StateError(
      'Incomplete oracle: parsed $parsedRows rows, found ${rowByPair.length} '
      'unique pairs, expected $expectedRows',
    );
  }

  final stateId = <String, int>{
    for (var index = 0; index < stateKeys.length; index++)
      stateKeys[index]: index,
  };
  final effectListId = <String, int>{
    for (var index = 0; index < effectListKeys.length; index++)
      effectListKeys[index]: index,
  };
  final dispositions = _enumValues(manifest, 'TransitionDisposition');
  final actions = (_map(manifest['actions'])).keys.toList(growable: false);
  final dispositionId = <String, int>{
    for (var index = 0; index < dispositions.length; index++)
      dispositions[index]: index,
  };
  final actionId = <String, int>{
    for (var index = 0; index < actions.length; index++) actions[index]: index,
  };

  final transitions = <Object?>[];
  for (final preKey in sortedPreStateKeys) {
    final row = <Object?>[];
    for (final eventKey in eventKeys) {
      final result = rowByPair['$preKey\u0000$eventKey'];
      if (result == null) {
        throw StateError('Missing oracle row for a state/event pair');
      }
      row.add([
        dispositionId[result.disposition]!,
        actionId[result.action]!,
        stateId[result.postStateKey]!,
        effectListId[result.effectListKey]!,
      ]);
    }
    transitions.add(row);
  }

  final manifestHash = manifestSha256(packageRoot);
  final modelHash = modelSha256(packageRoot);
  final config = File(
    '${packageRoot.path}/formal/SocketSafety.cfg',
  ).readAsStringSync();
  final artifact = <String, Object?>{
    'formatVersion': _formatVersion,
    'manifestSha256': manifestHash,
    'modelSha256': modelHash,
    'bounds': {
      'maxGeneration': _configConstant(config, 'MaxGeneration'),
      'maxTimerId': _configConstant(config, 'MaxTimerId'),
      'maxHeartbeatRef': _configConstant(config, 'MaxHeartbeatRef'),
      'maxRetryCount': _configConstant(config, 'MaxRetryCount'),
    },
    'counts': {
      'tlcStates': tlcStateCount,
      'protocolStates': stateKeys.length,
      'scopeExhaustedStates': scopeExhaustedStateCount,
      'oraclePreStates': sortedPreStateKeys.length,
      'events': eventKeys.length,
      'rows': expectedRows,
      'effectLists': effectListKeys.length,
    },
    'dispositions': dispositions,
    'actions': actions,
    'states': [for (final key in stateKeys) protocolStateByKey[key]],
    'preStateIds': [for (final key in sortedPreStateKeys) stateId[key]],
    'events': [for (final key in eventKeys) eventByKey[key]],
    'effectLists': [for (final key in effectListKeys) effectListByKey[key]],
    'transitions': transitions,
    'coverage': {
      'actions': _orderedCounts(actions, actionCounts),
      'dispositions': _orderedCounts(dispositions, dispositionCounts),
    },
  };

  final encoded = utf8.encode(jsonEncode(artifact));
  final compressed = gzip.encode(encoded);
  final output = File(options.output);
  if (options.check) {
    if (!output.existsSync() ||
        !_bytesEqual(output.readAsBytesSync(), compressed)) {
      stderr.writeln('Transition oracle is stale: ${output.path}');
      stderr.writeln('Run the formal TLC/oracle gate to regenerate it.');
      exitCode = 1;
      return;
    }
    stdout.writeln('Transition oracle is current ($expectedRows rows).');
    return;
  }
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(compressed);
  stdout.writeln(
    'Generated ${output.path}: $expectedRows rows, '
    '${compressed.length} compressed bytes.',
  );
}

Map<String, Map<String, String>> _shapes(Object? value) => _map(value).map(
  (key, fields) => MapEntry(key, _map(fields).cast<String, String>()),
);

Map<String, Object?> _normalizeRecord(
  Map<String, Object?> raw,
  Map<String, String> shape,
  Map<String, Map<String, String>> records,
) {
  final result = <String, Object?>{};
  for (final entry in shape.entries) {
    if (!raw.containsKey(entry.key)) {
      throw StateError('TLC record is missing ${entry.key}');
    }
    final value = raw[entry.key];
    if (entry.value.startsWith('record:')) {
      final recordName = entry.value.substring('record:'.length);
      result[entry.key] = _normalizeRecord(
        _map(value),
        records[recordName]!,
        records,
      );
    } else {
      result[entry.key] = value;
    }
  }
  return result;
}

Map<String, Object?> _map(Object? value) =>
    (value! as Map).cast<String, Object?>();

List<String> _enumValues(Map<String, Object?> manifest, String name) =>
    ((_map(manifest['enums']))[name]! as List<Object?>).cast<String>();

Map<String, int> _orderedCounts(
  List<String> vocabulary,
  Map<String, int> counts,
) => <String, int>{for (final value in vocabulary) value: counts[value] ?? 0};

String _canonical(Object? value) => jsonEncode(value);

int _configConstant(String config, String name) {
  final match = RegExp(
    '^\\s*$name\\s*=\\s*([0-9]+)\\s*\$',
    multiLine: true,
  ).firstMatch(config);
  if (match == null) throw StateError('Missing config constant $name');
  return int.parse(match.group(1)!);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _ParsedRow {
  const _ParsedRow({
    required this.disposition,
    required this.action,
    required this.postStateKey,
    required this.effectListKey,
  });

  final String disposition;
  final String action;
  final String postStateKey;
  final String effectListKey;
}

final class _Options {
  const _Options({
    required this.reachableDump,
    required this.oracleDump,
    required this.output,
    required this.check,
  });

  factory _Options.parse(List<String> arguments) {
    String? reachableDump;
    String? oracleDump;
    String? output;
    var check = false;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--reachable-dump':
          reachableDump = arguments[++index];
        case '--oracle-dump':
          oracleDump = arguments[++index];
        case '--output':
          output = arguments[++index];
        case '--check':
          check = true;
        default:
          throw FormatException('Unknown argument: ${arguments[index]}');
      }
    }
    if (reachableDump == null || oracleDump == null || output == null) {
      throw const FormatException(
        'Required: --reachable-dump PATH --oracle-dump PATH --output PATH',
      );
    }
    return _Options(
      reachableDump: reachableDump,
      oracleDump: oracleDump,
      output: output,
      check: check,
    );
  }

  final String reachableDump;
  final String oracleDump;
  final String output;
  final bool check;
}
