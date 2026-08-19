import 'dart:convert';
import 'dart:io';

import 'tla_value.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw const FormatException(
      'Usage: generate_channel_push_reachable.dart DUMP OUTPUT_DIR',
    );
  }
  final channelValues = <String, Object?>{};
  final pushValues = <String, Object?>{};
  var scopeExhausted = 0;
  for (final assignment in parseTlcDump(
    File(arguments[0]).readAsStringSync(),
  )) {
    if (assignment['scopeExhausted']! as bool) {
      scopeExhausted++;
      continue;
    }
    final channel = assignment['channel']!;
    final push = assignment['push']!;
    channelValues[jsonEncode(channel)] = channel;
    pushValues[jsonEncode(push)] = push;
  }
  final output = Directory(arguments[1])..createSync(recursive: true);
  _writeModule(
    File('${output.path}/ReachableChannelStates.tla'),
    'ReachableChannelStates',
    channelValues,
  );
  _writeModule(
    File('${output.path}/ReachablePushStates.tla'),
    'ReachablePushStates',
    pushValues,
  );
  stdout.writeln(
    'Generated ${channelValues.length} channel states and '
    '${pushValues.length} push states; $scopeExhausted boundary states.',
  );
}

void _writeModule(
  File file,
  String name,
  Map<String, Object?> values,
) {
  final sorted = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  file.writeAsStringSync(
    '-------------------- MODULE $name --------------------\n'
    '\\* Generated from the channel/push TLC safety dump.\n\n'
    '$name == {\n'
    '${sorted.map((entry) => encodeTlaValue(entry.value)).join(',\n')}\n'
    '}\n\n'
    '===================================================================\n',
  );
}
