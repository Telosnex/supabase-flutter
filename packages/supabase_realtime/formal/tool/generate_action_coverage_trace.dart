import 'dart:convert';
import 'dart:io';

import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_channel_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_channel_kernel.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_kernel.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_kernel.dart';

import 'tla_value.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final manifest = _map(
    jsonDecode(
      File('${packageRoot.path}/formal/manifest.json').readAsStringSync(),
    ),
  );
  final records = _shapes(manifest['records']);
  final traces = <Map<String, Object?>>[];

  await _socketCoverage(options.socketOracle, traces);

  final reachable = parseTlcDump(
    File(options.reachableDump).readAsStringSync(),
  ).where((entry) => entry['scopeExhausted'] == false).toList();
  final channelStates = reachable
      .map(
        (entry) => ChannelModelState.fromJson(
          _normalizeRecord(
            _map(entry['channel']),
            records['ChannelModelState']!,
            records,
          ),
        ),
      )
      .toSet()
      .toList();
  final pushStates = reachable
      .map(
        (entry) => PushModelState.fromJson(
          _normalizeRecord(
            _map(entry['push']),
            records['PushModelState']!,
            records,
          ),
        ),
      )
      .toSet()
      .toList();

  final channelRows = _channelRows(
    options.channelDump,
    records,
    _shapes(manifest['channelEvents']),
  );
  await _channelCoverage(channelStates, channelRows, traces);

  final pushRows = _pushRows(
    options.pushDump,
    records,
    _shapes(manifest['pushEvents']),
  );
  await _pushCoverage(pushStates, pushRows, traces);

  File(options.output).writeAsStringSync(
    '${traces.map(jsonEncode).join('\n')}\n',
  );
  final actions = traces.map((trace) => trace['action']).toSet();
  stdout.writeln(
    'Generated ${traces.length} prefix trace entries covering '
    '${actions.length} accepted lifecycle actions.',
  );
}

Future<void> _socketCoverage(
  String artifactPath,
  List<Map<String, Object?>> traces,
) async {
  final artifact = _map(
    jsonDecode(
      utf8.decode(gzip.decode(File(artifactPath).readAsBytesSync())),
    ),
  );
  final states = (artifact['states']! as List<Object?>)
      .map((value) => SocketModelState.fromJson(_map(value)))
      .toList();
  final events = (artifact['events']! as List<Object?>)
      .map((value) => SocketModelEvent.fromJson(_map(value)))
      .toList();
  final preStateIds = (artifact['preStateIds']! as List<Object?>)
      .map((value) => (value! as num).toInt())
      .toList();
  final actions = (artifact['actions']! as List<Object?>).cast<String>();
  final dispositions = (artifact['dispositions']! as List<Object?>)
      .cast<String>();
  final matrix = artifact['transitions']! as List<Object?>;
  final representatives = <String, _SocketRepresentative>{};
  for (var row = 0; row < preStateIds.length; row++) {
    final cells = matrix[row]! as List<Object?>;
    for (var eventIndex = 0; eventIndex < cells.length; eventIndex++) {
      final cell = (cells[eventIndex]! as List<Object?>)
          .map((value) => (value! as num).toInt())
          .toList();
      final action = actions[cell[1]];
      if (dispositions[cell[0]] != 'rejected') {
        representatives.putIfAbsent(
          action,
          () => _SocketRepresentative(
            preState: states[preStateIds[row]],
            event: events[eventIndex],
          ),
        );
      }
    }
  }
  final paths = _paths<SocketModelState, SocketModelEvent>(
    roots: [RealtimeSocketKernel.initialState],
    states: states,
    events: events,
    key: (state) => jsonEncode(state.toJson()),
    step: (state, event) {
      final result = const RealtimeSocketKernel().step(state, event);
      return result.disposition == TransitionDisposition.applied
          ? result.postState
          : null;
    },
  );
  for (final entry in representatives.entries) {
    final path = paths[jsonEncode(entry.value.preState.toJson())]!;
    final driver = RealtimeSocketDriver(
      executeEffect: (effect, context) {},
      traceSink: traces.add,
      instance: 'coverage:socket:${entry.key}',
    );
    for (final event in path.events) {
      await driver.dispatch(event);
    }
    await driver.dispatch(entry.value.event);
  }
  final expected = SocketAction.values
      .where((action) => action != SocketAction.rejectContractViolation)
      .length;
  if (representatives.length != expected) {
    throw StateError('Socket trace action coverage is incomplete');
  }
}

Future<void> _channelCoverage(
  List<ChannelModelState> states,
  List<_ChannelRow> rows,
  List<Map<String, Object?>> traces,
) async {
  final events = rows.map((row) => row.event).toSet().toList();
  final roots = [
    RealtimeChannelKernel.initialState(channelId: 1),
    RealtimeChannelKernel.initialState(channelId: 2),
  ];
  final paths = _paths<ChannelModelState, ChannelModelEvent>(
    roots: roots,
    states: states,
    events: events,
    key: (state) => jsonEncode(state.toJson()),
    step: (state, event) {
      final result = const RealtimeChannelKernel().step(state, event);
      return result.disposition == TransitionDisposition.applied
          ? result.postState
          : null;
    },
  );
  final representatives = <String, _ChannelRow>{};
  for (final row in rows.where((row) => row.disposition != 'rejected')) {
    representatives.putIfAbsent(row.action, () => row);
  }
  for (final entry in representatives.entries) {
    final path = paths[jsonEncode(entry.value.preState.toJson())]!;
    final driver = RealtimeChannelDriver(
      channelId: path.root.channelId,
      executeEffect: (effect, metadata) {},
      traceSink: traces.add,
      instance: 'coverage:channel:${entry.key}',
    );
    for (final event in path.events) {
      await driver.dispatch(event);
    }
    await driver.dispatch(entry.value.event);
  }
  final expected = ChannelModelAction.values
      .where(
        (action) => action != ChannelModelAction.rejectChannelContractViolation,
      )
      .length;
  if (representatives.length != expected) {
    throw StateError('Channel trace action coverage is incomplete');
  }
}

Future<void> _pushCoverage(
  List<PushModelState> states,
  List<_PushRow> rows,
  List<Map<String, Object?>> traces,
) async {
  final events = rows.map((row) => row.event).toSet().toList();
  final paths = _paths<PushModelState, PushModelEvent>(
    roots: [RealtimePushKernel.initialState],
    states: states,
    events: events,
    key: (state) => jsonEncode(state.toJson()),
    step: (state, event) {
      final result = const RealtimePushKernel().step(state, event);
      return result.disposition == TransitionDisposition.applied
          ? result.postState
          : null;
    },
  );
  final representatives = <String, _PushRow>{};
  for (final row in rows.where((row) => row.disposition != 'rejected')) {
    representatives.putIfAbsent(row.action, () => row);
  }
  for (final entry in representatives.entries) {
    final path = paths[jsonEncode(entry.value.preState.toJson())]!;
    final driver = RealtimePushDriver(
      executeEffect: (effect, metadata) {},
      traceSink: traces.add,
      instance: 'coverage:push:${entry.key}',
    );
    for (final event in path.events) {
      await driver.dispatch(event);
    }
    await driver.dispatch(entry.value.event);
  }
  final expected = PushModelAction.values
      .where((action) => action != PushModelAction.rejectPushContractViolation)
      .length;
  if (representatives.length != expected) {
    throw StateError('Push trace action coverage is incomplete');
  }
}

Map<String, _Path<S, E>> _paths<S, E>({
  required List<S> roots,
  required List<S> states,
  required List<E> events,
  required String Function(S state) key,
  required S? Function(S state, E event) step,
}) {
  final known = <String, S>{for (final state in states) key(state): state};
  final paths = <String, _Path<S, E>>{};
  final queue = <S>[];
  for (final root in roots) {
    paths[key(root)] = _Path(root: root, events: const []);
    queue.add(root);
  }
  for (var cursor = 0; cursor < queue.length; cursor++) {
    final state = queue[cursor];
    final statePath = paths[key(state)]!;
    for (final event in events) {
      final postState = step(state, event);
      if (postState == null) continue;
      final postKey = key(postState);
      if (!known.containsKey(postKey) || paths.containsKey(postKey)) continue;
      paths[postKey] = _Path(
        root: statePath.root,
        events: [...statePath.events, event],
      );
      queue.add(known[postKey] as S);
    }
  }
  return paths;
}

List<_ChannelRow> _channelRows(
  String dump,
  Map<String, Map<String, String>> records,
  Map<String, Map<String, String>> eventShapes,
) => parseTlcDump(File(dump).readAsStringSync()).map((entry) {
  final state = ChannelModelState.fromJson(
    _normalizeRecord(
      _map(entry['preState']),
      records['ChannelModelState']!,
      records,
    ),
  );
  final rawEvent = _map(entry['event']);
  final kind = rawEvent['kind']! as String;
  final event = ChannelModelEvent.fromJson({
    'kind': kind,
    ..._normalizeRecord(rawEvent, eventShapes[kind]!, records),
  });
  final result = _map(entry['result']);
  return _ChannelRow(
    preState: state,
    event: event,
    action: result['action']! as String,
    disposition: result['disposition']! as String,
  );
}).toList();

List<_PushRow> _pushRows(
  String dump,
  Map<String, Map<String, String>> records,
  Map<String, Map<String, String>> eventShapes,
) => parseTlcDump(File(dump).readAsStringSync()).map((entry) {
  final state = PushModelState.fromJson(
    _normalizeRecord(
      _map(entry['preState']),
      records['PushModelState']!,
      records,
    ),
  );
  final rawEvent = _map(entry['event']);
  final kind = rawEvent['kind']! as String;
  final event = PushModelEvent.fromJson({
    'kind': kind,
    ..._normalizeRecord(rawEvent, eventShapes[kind]!, records),
  });
  final result = _map(entry['result']);
  return _PushRow(
    preState: state,
    event: event,
    action: result['action']! as String,
    disposition: result['disposition']! as String,
  );
}).toList();

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

final class _Path<S, E> {
  const _Path({required this.root, required this.events});
  final S root;
  final List<E> events;
}

final class _SocketRepresentative {
  const _SocketRepresentative({required this.preState, required this.event});
  final SocketModelState preState;
  final SocketModelEvent event;
}

final class _ChannelRow {
  const _ChannelRow({
    required this.preState,
    required this.event,
    required this.action,
    required this.disposition,
  });
  final ChannelModelState preState;
  final ChannelModelEvent event;
  final String action;
  final String disposition;
}

final class _PushRow {
  const _PushRow({
    required this.preState,
    required this.event,
    required this.action,
    required this.disposition,
  });
  final PushModelState preState;
  final PushModelEvent event;
  final String action;
  final String disposition;
}

final class _Options {
  const _Options({
    required this.socketOracle,
    required this.channelDump,
    required this.pushDump,
    required this.reachableDump,
    required this.output,
  });

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index += 2) {
      values[arguments[index]] = File(arguments[index + 1]).absolute.path;
    }
    const required = {
      '--socket-oracle',
      '--channel-dump',
      '--push-dump',
      '--reachable-dump',
      '--output',
    };
    if (!values.keys.toSet().containsAll(required)) {
      throw const FormatException('Missing action coverage trace arguments');
    }
    return _Options(
      socketOracle: values['--socket-oracle']!,
      channelDump: values['--channel-dump']!,
      pushDump: values['--push-dump']!,
      reachableDump: values['--reachable-dump']!,
      output: values['--output']!,
    );
  }

  final String socketOracle;
  final String channelDump;
  final String pushDump;
  final String reachableDump;
  final String output;
}
