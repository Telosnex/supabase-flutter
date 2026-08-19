import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_channel_kernel.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_kernel.dart';

import 'tla_value.dart';

const _equality = DeepCollectionEquality();

void main(List<String> arguments) {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final manifest = _map(
    jsonDecode(
      File('${packageRoot.path}/formal/manifest.json').readAsStringSync(),
    ),
  );
  final records = _shapes(manifest['records']);
  final channelEvents = _shapes(manifest['channelEvents']);
  final channelEffects = _shapes(manifest['channelEffects']);
  final pushEvents = _shapes(manifest['pushEvents']);
  final pushEffects = _shapes(manifest['pushEffects']);
  final reachableAssignments = parseTlcDump(
    File(options.reachableDump).readAsStringSync(),
  ).where((assignment) => assignment['scopeExhausted'] == false).toList();
  final reachableChannels = reachableAssignments
      .map(
        (assignment) => _normalizeRecord(
          _map(assignment['channel']),
          records['ChannelModelState']!,
          records,
        ),
      )
      .toList();
  final reachablePushes = reachableAssignments
      .map(
        (assignment) => _normalizeRecord(
          _map(assignment['push']),
          records['PushModelState']!,
          records,
        ),
      )
      .toList();

  final channel = _verifyMachine(
    dump: options.channelDump,
    stateShape: records['ChannelModelState']!,
    records: records,
    eventShapes: channelEvents,
    effectShapes: channelEffects,
    actionVocabulary: ChannelModelAction.values
        .map((value) => value.wireName)
        .toList(),
    initialStates: [
      for (var channelId = 1; channelId <= 2; channelId++)
        RealtimeChannelKernel.initialState(channelId: channelId).toJson(),
    ],
    reachableStates: reachableChannels,
    compare: (preState, event) => const RealtimeChannelKernel()
        .step(
          ChannelModelState.fromJson(preState),
          ChannelModelEvent.fromJson(event),
        )
        .toJson(),
  );
  final push = _verifyMachine(
    dump: options.pushDump,
    stateShape: records['PushModelState']!,
    records: records,
    eventShapes: pushEvents,
    effectShapes: pushEffects,
    actionVocabulary: PushModelAction.values
        .map((value) => value.wireName)
        .toList(),
    initialStates: [RealtimePushKernel.initialState.toJson()],
    reachableStates: reachablePushes,
    compare: (preState, event) => const RealtimePushKernel()
        .step(
          PushModelState.fromJson(preState),
          PushModelEvent.fromJson(event),
        )
        .toJson(),
  );

  final report = {'channel': channel.toJson(), 'push': push.toJson()};
  if (options.report != null) {
    File(options.report!).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
  }
  stdout.writeln(
    'Verified ${channel.rows} channel and ${push.rows} push transitions '
    'against TLC; ${channel.actionsCovered + push.actionsCovered} actions '
    'covered.',
  );
}

_MachineReport _verifyMachine({
  required String dump,
  required Map<String, String> stateShape,
  required Map<String, Map<String, String>> records,
  required Map<String, Map<String, String>> eventShapes,
  required Map<String, Map<String, String>> effectShapes,
  required List<String> actionVocabulary,
  required List<Map<String, Object?>> initialStates,
  required List<Map<String, Object?>> reachableStates,
  required Map<String, Object?> Function(
    Map<String, Object?> state,
    Map<String, Object?> event,
  )
  compare,
}) {
  final preStates = <String>{};
  final events = <String>{};
  final pairs = <String>{};
  final actionCounts = <String, int>{};
  final dispositionCounts = <String, int>{};
  final parsedRows = <_OracleRow>[];
  var rows = 0;
  for (final assignment in parseTlcDump(File(dump).readAsStringSync())) {
    rows++;
    final preState = _normalizeRecord(
      _map(assignment['preState']),
      stateShape,
      records,
    );
    final fullEvent = _map(assignment['event']);
    final eventKind = fullEvent['kind']! as String;
    final eventShape = eventShapes[eventKind];
    if (eventShape == null) throw StateError('Unknown event $eventKind');
    final event = <String, Object?>{
      'kind': eventKind,
      ..._normalizeRecord(fullEvent, eventShape, records),
    };
    final result = _map(assignment['result']);
    final compactEffects = <Object?>[];
    for (final rawEffect in result['effects']! as List<Object?>) {
      final fullEffect = _map(rawEffect);
      final effectKind = fullEffect['kind']! as String;
      final effectShape = effectShapes[effectKind];
      if (effectShape == null) throw StateError('Unknown effect $effectKind');
      compactEffects.add({
        'kind': effectKind,
        ..._normalizeRecord(fullEffect, effectShape, records),
      });
    }
    final expected = <String, Object?>{
      'disposition': result['disposition'],
      'action': result['action'],
      'postState': _normalizeRecord(
        _map(result['postState']),
        stateShape,
        records,
      ),
      'effects': compactEffects,
    };
    final actual = compare(preState, event);
    if (!_equality.equals(actual, expected)) {
      throw StateError(
        'Oracle mismatch at row $rows\n'
        'preState=${jsonEncode(preState)}\n'
        'event=${jsonEncode(event)}\n'
        'expected=${jsonEncode(expected)}\n'
        'actual=${jsonEncode(actual)}',
      );
    }
    parsedRows.add(
      _OracleRow(preState: preState, event: event, expected: expected),
    );
    final preKey = jsonEncode(preState);
    final eventKey = jsonEncode(event);
    preStates.add(preKey);
    events.add(eventKey);
    if (!pairs.add('$preKey\u0000$eventKey')) {
      throw StateError('Duplicate state/event oracle row');
    }
    final action = result['action']! as String;
    final disposition = result['disposition']! as String;
    actionCounts.update(action, (count) => count + 1, ifAbsent: () => 1);
    dispositionCounts.update(
      disposition,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final expectedRows = preStates.length * events.length;
  if (rows != expectedRows || pairs.length != expectedRows) {
    throw StateError(
      'Incomplete Cartesian product: $rows rows, ${pairs.length} pairs, '
      '$expectedRows expected',
    );
  }
  final missingActions = actionVocabulary
      .where((action) => !actionCounts.containsKey(action))
      .toList();
  if (missingActions.isNotEmpty) {
    throw StateError('Uncovered actions: ${missingActions.join(', ')}');
  }
  final prefixCoverage = _verifyShortestPrefixes(
    rows: parsedRows,
    initialStates: initialStates,
    reachableStates: reachableStates,
    compare: compare,
  );
  return _MachineReport(
    rows: rows,
    preStates: preStates.length,
    events: events.length,
    actionsCovered: actionCounts.length,
    actionCounts: actionCounts,
    dispositionCounts: dispositionCounts,
    prefixStates: prefixCoverage.states,
    maxPrefixDepth: prefixCoverage.maxDepth,
  );
}

_PrefixCoverage _verifyShortestPrefixes({
  required List<_OracleRow> rows,
  required List<Map<String, Object?>> initialStates,
  required List<Map<String, Object?>> reachableStates,
  required Map<String, Object?> Function(
    Map<String, Object?> state,
    Map<String, Object?> event,
  )
  compare,
}) {
  final preStates = <String, Map<String, Object?>>{};
  final allStates = <String, Map<String, Object?>>{
    for (final state in reachableStates) jsonEncode(state): state,
  };
  final events = <String, Map<String, Object?>>{};
  for (final row in rows) {
    final key = jsonEncode(row.preState);
    preStates[key] = row.preState;
    events[jsonEncode(row.event)] = row.event;
  }
  final paths = <String, List<Map<String, Object?>>>{};
  final roots = <String, Map<String, Object?>>{};
  final queue = <String>[];
  for (final initial in initialStates) {
    final key = jsonEncode(initial);
    if (!preStates.containsKey(key)) continue;
    paths[key] = const [];
    roots[key] = initial;
    queue.add(key);
  }
  for (var cursor = 0; cursor < queue.length; cursor++) {
    final preKey = queue[cursor];
    final preState = allStates[preKey]!;
    for (final event in events.values) {
      final result = compare(preState, event);
      if (result['disposition'] != 'applied') continue;
      final postState = _map(result['postState']);
      final postKey = jsonEncode(postState);
      if (!allStates.containsKey(postKey) || paths.containsKey(postKey)) {
        continue;
      }
      paths[postKey] = [...paths[preKey]!, event];
      roots[postKey] = roots[preKey]!;
      queue.add(postKey);
    }
  }
  final missing = preStates.keys.where((key) => !paths.containsKey(key)).length;
  if (missing != 0) {
    final examples = preStates.keys
        .where((key) => !paths.containsKey(key))
        .take(3)
        .join('\n');
    throw StateError(
      '$missing oracle pre-states lack an initial-state prefix:\n$examples',
    );
  }
  var maxDepth = 0;
  for (final entry in paths.entries) {
    var current = roots[entry.key]!;
    for (final event in entry.value) {
      current = _map(compare(current, event)['postState']);
    }
    if (jsonEncode(current) != entry.key) {
      throw StateError(
        'A generated shortest prefix does not reach its state:\n'
        'expected=${entry.key}\nactual=${jsonEncode(current)}\n'
        'events=${jsonEncode(entry.value)}',
      );
    }
    if (entry.value.length > maxDepth) maxDepth = entry.value.length;
  }
  return _PrefixCoverage(states: paths.length, maxDepth: maxDepth);
}

Map<String, Object?> _normalizeRecord(
  Map<String, Object?> raw,
  Map<String, String> shape,
  Map<String, Map<String, String>> records,
) => <String, Object?>{
  for (final entry in shape.entries)
    entry.key: entry.value.startsWith('record:')
        ? _normalizeRecord(
            _map(raw[entry.key]),
            records[entry.value.substring('record:'.length)]!,
            records,
          )
        : raw[entry.key],
};

Map<String, Map<String, String>> _shapes(Object? value) => _map(value).map(
  (key, fields) => MapEntry(key, _map(fields).cast<String, String>()),
);

Map<String, Object?> _map(Object? value) =>
    (value! as Map).cast<String, Object?>();

final class _MachineReport {
  const _MachineReport({
    required this.rows,
    required this.preStates,
    required this.events,
    required this.actionsCovered,
    required this.actionCounts,
    required this.dispositionCounts,
    required this.prefixStates,
    required this.maxPrefixDepth,
  });

  final int rows;
  final int preStates;
  final int events;
  final int actionsCovered;
  final Map<String, int> actionCounts;
  final Map<String, int> dispositionCounts;
  final int prefixStates;
  final int maxPrefixDepth;

  Map<String, Object?> toJson() => {
    'rows': rows,
    'preStates': preStates,
    'events': events,
    'actionsCovered': actionsCovered,
    'actionCounts': actionCounts,
    'dispositionCounts': dispositionCounts,
    'prefixStates': prefixStates,
    'maxPrefixDepth': maxPrefixDepth,
  };
}

final class _OracleRow {
  const _OracleRow({
    required this.preState,
    required this.event,
    required this.expected,
  });

  final Map<String, Object?> preState;
  final Map<String, Object?> event;
  final Map<String, Object?> expected;
}

final class _PrefixCoverage {
  const _PrefixCoverage({required this.states, required this.maxDepth});

  final int states;
  final int maxDepth;
}

final class _Options {
  const _Options({
    required this.channelDump,
    required this.pushDump,
    required this.reachableDump,
    required this.report,
  });

  factory _Options.parse(List<String> arguments) {
    String? channelDump;
    String? pushDump;
    String? report;
    String? reachableDump;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--channel-dump':
          channelDump = arguments[++index];
        case '--push-dump':
          pushDump = arguments[++index];
        case '--report':
          report = arguments[++index];
        case '--reachable-dump':
          reachableDump = arguments[++index];
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
      report: report,
    );
  }

  final String channelDump;
  final String pushDump;
  final String reachableDump;
  final String? report;
}
