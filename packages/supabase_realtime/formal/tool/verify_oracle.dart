import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_kernel.dart';

import 'formal_hashes.dart';

const _deepEquality = DeepCollectionEquality();

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single.startsWith('-'))) {
    stderr.writeln('Usage: dart run formal/tool/verify_oracle.dart [PATH]');
    exitCode = 64;
    return;
  }
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final path = arguments.isEmpty
      ? '${packageRoot.path}/formal/oracle/socket_transition_oracle.json.gz'
      : arguments.single;
  final artifact = _map(
    jsonDecode(utf8.decode(gzip.decode(File(path).readAsBytesSync()))),
  );

  _expect(artifact['formatVersion'] == 1, 'Unknown oracle format version');
  _expect(
    artifact['manifestSha256'] == manifestSha256(packageRoot),
    'Oracle manifest hash is stale',
  );
  _expect(
    artifact['modelSha256'] == modelSha256(packageRoot),
    'Oracle model hash is stale',
  );
  _expect(
    artifact['manifestSha256'] == realtimeFormalManifestSha256,
    'Generated Dart schema has a different manifest hash',
  );

  final bounds = _map(artifact['bounds']);
  final counts = _map(artifact['counts']);
  final dispositions = _strings(artifact['dispositions']);
  final actions = _strings(artifact['actions']);
  final stateJson = _maps(artifact['states']);
  final preStateIds = _integers(artifact['preStateIds']);
  final eventJson = _maps(artifact['events']);
  final effectListJson = (artifact['effectLists']! as List<Object?>)
      .map((value) => _maps(value))
      .toList(growable: false);
  final transitions = artifact['transitions']! as List<Object?>;

  _expect(
    dispositions.map(TransitionDisposition.fromWire).length ==
        TransitionDisposition.values.length,
    'Disposition vocabulary is incomplete',
  );
  _expect(
    _deepEquality.equals(
      actions,
      SocketAction.values.map((value) => value.wireName).toList(),
    ),
    'Action vocabulary does not match generated Dart',
  );
  _expect(
    stateJson.length == _integer(counts['protocolStates']),
    'State count metadata is wrong',
  );
  _expect(
    preStateIds.length == _integer(counts['oraclePreStates']),
    'Pre-state count metadata is wrong',
  );
  _expect(
    eventJson.length == _integer(counts['events']),
    'Event count metadata is wrong',
  );
  _expect(
    transitions.length == preStateIds.length,
    'Transition matrix has the wrong number of state rows',
  );
  _expect(
    preStateIds.toSet().length == preStateIds.length,
    'Oracle contains duplicate pre-state IDs',
  );
  _expect(
    eventJson.map(jsonEncode).toSet().length == eventJson.length,
    'Oracle contains duplicate events',
  );

  final states = stateJson
      .map(SocketModelState.fromJson)
      .toList(growable: false);
  final events = eventJson
      .map(SocketModelEvent.fromJson)
      .toList(growable: false);
  final effectLists = effectListJson
      .map(
        (list) => list.map(SocketModelEffect.fromJson).toList(growable: false),
      )
      .toList(growable: false);
  final kernel = RealtimeSocketKernel(
    retryCountCap: _integer(bounds['maxRetryCount']),
  );
  final observedActionCounts = <String, int>{};
  final observedDispositionCounts = <String, int>{};
  var comparedRows = 0;

  for (var preIndex = 0; preIndex < preStateIds.length; preIndex++) {
    final preStateId = preStateIds[preIndex];
    _expect(
      preStateId >= 0 && preStateId < states.length,
      'Pre-state ID $preStateId is out of range',
    );
    final cells = transitions[preIndex]! as List<Object?>;
    _expect(
      cells.length == events.length,
      'Transition row $preIndex has ${cells.length} cells; '
      'expected ${events.length}',
    );
    final preState = states[preStateId];
    for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
      final cell = _integers(cells[eventIndex]);
      _expect(cell.length == 4, 'Transition cell must contain four IDs');
      final dispositionId = cell[0];
      final actionId = cell[1];
      final postStateId = cell[2];
      final effectListId = cell[3];
      _expect(
        dispositionId >= 0 && dispositionId < dispositions.length,
        'Disposition ID is out of range',
      );
      _expect(
        actionId >= 0 && actionId < actions.length,
        'Action ID is out of range',
      );
      _expect(
        postStateId >= 0 && postStateId < states.length,
        'Post-state ID is out of range',
      );
      _expect(
        effectListId >= 0 && effectListId < effectLists.length,
        'Effect-list ID is out of range',
      );

      final expected = <String, Object?>{
        'disposition': dispositions[dispositionId],
        'action': actions[actionId],
        'postState': states[postStateId].toJson(),
        'effects': effectLists[effectListId]
            .map((effect) => effect.toJson())
            .toList(),
      };
      final actual = kernel.step(preState, events[eventIndex]).toJson();
      if (!_deepEquality.equals(actual, expected)) {
        stderr
          ..writeln('Oracle mismatch at row $comparedRows')
          ..writeln('preState: ${jsonEncode(preState.toJson())}')
          ..writeln('event: ${jsonEncode(events[eventIndex].toJson())}')
          ..writeln('expected: ${jsonEncode(expected)}')
          ..writeln('actual: ${jsonEncode(actual)}');
        exitCode = 1;
        return;
      }
      observedActionCounts.update(
        actions[actionId],
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      observedDispositionCounts.update(
        dispositions[dispositionId],
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      comparedRows++;
    }
  }

  _expect(
    comparedRows == _integer(counts['rows']),
    'Compared $comparedRows rows; metadata declares ${counts['rows']}',
  );
  final coverage = _map(artifact['coverage']);
  _expect(
    _deepEquality.equals(
      observedActionCounts,
      _map(coverage['actions']).cast<String, int>(),
    ),
    'Action coverage metadata is wrong',
  );
  _expect(
    _deepEquality.equals(
      observedDispositionCounts,
      _map(coverage['dispositions']).cast<String, int>(),
    ),
    'Disposition coverage metadata is wrong',
  );
  final uncoveredActions = actions
      .where((action) => (observedActionCounts[action] ?? 0) == 0)
      .toList();
  _expect(
    uncoveredActions.isEmpty,
    'Oracle does not cover actions: ${uncoveredActions.join(', ')}',
  );
  final prefixDepth = _verifyShortestPrefixes(
    kernel: kernel,
    states: states,
    events: events,
    preStateIds: preStateIds,
  );

  stdout.writeln(
    'Verified $comparedRows Dart transitions against TLC '
    '(${states.length} reachable states, ${events.length} events, '
    '${actions.length} actions covered, shortest-prefix depth $prefixDepth).',
  );
}

int _verifyShortestPrefixes({
  required RealtimeSocketKernel kernel,
  required List<SocketModelState> states,
  required List<SocketModelEvent> events,
  required List<int> preStateIds,
}) {
  final stateIds = <SocketModelState, int>{
    for (var stateId = 0; stateId < states.length; stateId++)
      states[stateId]: stateId,
  };
  final initialId = states.indexOf(RealtimeSocketKernel.initialState);
  _expect(initialId >= 0, 'Oracle omits the socket initial state');
  final paths = <int, List<int>>{initialId: const []};
  final queue = <int>[initialId];
  for (var cursor = 0; cursor < queue.length; cursor++) {
    final stateId = queue[cursor];
    for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
      final result = kernel.step(states[stateId], events[eventIndex]);
      if (result.disposition != TransitionDisposition.applied) continue;
      final postStateId = stateIds[result.postState];
      if (postStateId == null || paths.containsKey(postStateId)) continue;
      paths[postStateId] = [...paths[stateId]!, eventIndex];
      queue.add(postStateId);
    }
  }
  _expect(
    preStateIds.every(paths.containsKey),
    'Some socket oracle pre-states lack an initial-state prefix',
  );
  var maxDepth = 0;
  for (final entry in paths.entries.where(
    (entry) => preStateIds.contains(entry.key),
  )) {
    var state = RealtimeSocketKernel.initialState;
    for (final eventIndex in entry.value) {
      state = kernel.step(state, events[eventIndex]).postState;
    }
    _expect(state == states[entry.key], 'A socket prefix reaches wrong state');
    if (entry.value.length > maxDepth) maxDepth = entry.value.length;
  }
  return maxDepth;
}

Map<String, Object?> _map(Object? value) =>
    (value! as Map).cast<String, Object?>();

List<Map<String, Object?>> _maps(Object? value) =>
    (value! as List<Object?>).map(_map).toList(growable: false);

List<String> _strings(Object? value) =>
    (value! as List<Object?>).cast<String>();

List<int> _integers(Object? value) =>
    (value! as List<Object?>).map(_integer).toList(growable: false);

int _integer(Object? value) => (value! as num).toInt();

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
