import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _generatedNotice = 'GENERATED FILE. DO NOT EDIT.';
const _dartReservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

void main(List<String> arguments) {
  final checkOnly = arguments.contains('--check');
  final unknown = arguments.where((argument) => argument != '--check').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown arguments: ${unknown.join(' ')}');
    exitCode = 64;
    return;
  }

  final packageRoot = File.fromUri(Platform.script).parent.parent.parent;
  final manifestFile = File('${packageRoot.path}/formal/manifest.json');
  final manifestBytes = manifestFile.readAsBytesSync();
  final manifest = Manifest.parse(
    jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>,
  );
  final manifestHash = sha256.convert(manifestBytes).toString();

  final outputs = <String, String>{
    '${packageRoot.path}/formal/generated/KernelSchema.tla': _generateTla(
      manifest,
      manifestHash,
    ),
    '${packageRoot.path}/lib/src/kernel/generated/model_schema.dart':
        _formatDart(_generateDart(manifest, manifestHash)),
  };

  var stale = false;
  for (final entry in outputs.entries) {
    final file = File(entry.key);
    if (checkOnly) {
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        stderr.writeln('Generated file is stale: ${entry.key}');
        stale = true;
      }
      continue;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
    stdout.writeln('Generated ${entry.key}');
  }

  if (stale) {
    stderr.writeln(
      'Run: dart run formal/tool/generate_schema.dart',
    );
    exitCode = 1;
  }
}

String _generateTla(Manifest manifest, String hash) {
  final out = StringBuffer()
    ..writeln(
      '------------------------ MODULE '
      'KernelSchema ------------------------',
    )
    ..writeln('\\* $_generatedNotice')
    ..writeln('\\* Manifest SHA-256: $hash')
    ..writeln('\\* Schema version: ${manifest.schemaVersion}')
    ..writeln()
    ..writeln('EXTENDS Integers, Sequences')
    ..writeln();

  for (final entry in manifest.enums.entries) {
    out
      ..writeln('${entry.key}Values == {')
      ..writeln(
        entry.value.map((value) => '    ${_tlaString(value)}').join(',\n'),
      )
      ..writeln('}')
      ..writeln();
  }

  for (final entry in manifest.records.entries) {
    out
      ..writeln('${entry.key}Fields == {')
      ..writeln(
        entry.value.keys.map((name) => '    ${_tlaString(name)}').join(',\n'),
      )
      ..writeln('}')
      ..writeln();
  }

  _writeTlaStringSet(out, 'EventKinds', manifest.events.keys);
  _writeTlaStringSet(out, 'ActionIds', manifest.actions.keys);
  _writeTlaStringSet(out, 'EffectKinds', manifest.effects.keys);
  _writeTlaStringSet(out, 'ChannelEventKinds', manifest.channelEvents.keys);
  _writeTlaStringSet(out, 'ChannelActionIds', manifest.channelActions.keys);
  _writeTlaStringSet(out, 'ChannelEffectKinds', manifest.channelEffects.keys);
  _writeTlaStringSet(out, 'PushEventKinds', manifest.pushEvents.keys);
  _writeTlaStringSet(out, 'PushActionIds', manifest.pushActions.keys);
  _writeTlaStringSet(out, 'PushEffectKinds', manifest.pushEffects.keys);
  _writeTlaStringSet(
    out,
    'TraceRequiredFields',
    manifest.traceRequiredFields,
  );
  _writeTlaStringSet(out, 'TraceIdentityFields', manifest.traceIdentityFields);

  out
    ..writeln('ManifestSchemaVersion == ${manifest.schemaVersion}')
    ..writeln('ManifestSha256 == ${_tlaString(hash)}')
    ..writeln()
    ..writeln(
      '===================================='
      '=================================',
    );
  return out.toString();
}

void _writeTlaStringSet(
  StringBuffer out,
  String name,
  Iterable<String> values,
) {
  out
    ..writeln('$name == {')
    ..writeln(values.map((value) => '    ${_tlaString(value)}').join(',\n'))
    ..writeln('}')
    ..writeln();
}

String _generateDart(Manifest manifest, String hash) {
  final out = StringBuffer()
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln('// $_generatedNotice')
    ..writeln('// Manifest SHA-256: $hash')
    ..writeln('// Schema version: ${manifest.schemaVersion}')
    ..writeln()
    ..writeln("const realtimeFormalManifestSha256 = '$hash';")
    ..writeln(
      'const realtimeFormalSchemaVersion = ${manifest.schemaVersion};',
    )
    ..writeln();

  for (final entry in manifest.enums.entries) {
    _writeDartEnum(out, entry.key, entry.value);
  }
  _writeDartEnum(out, 'SocketEventKind', manifest.events.keys.toList());
  _writeDartEnum(out, 'SocketAction', manifest.actions.keys.toList());
  _writeDartEnum(out, 'SocketEffectKind', manifest.effects.keys.toList());
  _writeDartEnum(
    out,
    'ChannelModelEventKind',
    manifest.channelEvents.keys.toList(),
  );
  _writeDartEnum(
    out,
    'ChannelModelAction',
    manifest.channelActions.keys.toList(),
  );
  _writeDartEnum(
    out,
    'ChannelModelEffectKind',
    manifest.channelEffects.keys.toList(),
  );
  _writeDartEnum(
    out,
    'PushModelEventKind',
    manifest.pushEvents.keys.toList(),
  );
  _writeDartEnum(
    out,
    'PushModelAction',
    manifest.pushActions.keys.toList(),
  );
  _writeDartEnum(
    out,
    'PushModelEffectKind',
    manifest.pushEffects.keys.toList(),
  );

  for (final entry in manifest.records.entries) {
    _writeDartRecord(out, entry.key, entry.value);
  }

  _writeDartUnion(
    out: out,
    className: 'SocketModelEvent',
    enumName: 'SocketEventKind',
    variants: manifest.events,
  );
  _writeDartUnion(
    out: out,
    className: 'SocketModelEffect',
    enumName: 'SocketEffectKind',
    variants: manifest.effects,
  );
  _writeDartUnion(
    out: out,
    className: 'ChannelModelEvent',
    enumName: 'ChannelModelEventKind',
    variants: manifest.channelEvents,
  );
  _writeDartUnion(
    out: out,
    className: 'ChannelModelEffect',
    enumName: 'ChannelModelEffectKind',
    variants: manifest.channelEffects,
  );
  _writeDartUnion(
    out: out,
    className: 'PushModelEvent',
    enumName: 'PushModelEventKind',
    variants: manifest.pushEvents,
  );
  _writeDartUnion(
    out: out,
    className: 'PushModelEffect',
    enumName: 'PushModelEffectKind',
    variants: manifest.pushEffects,
  );
  _writeTransitionResult(
    out,
    resultName: 'SocketTransitionResult',
    actionName: 'SocketAction',
    stateName: 'SocketModelState',
    effectName: 'SocketModelEffect',
  );
  _writeTransitionResult(
    out,
    resultName: 'ChannelTransitionResult',
    actionName: 'ChannelModelAction',
    stateName: 'ChannelModelState',
    effectName: 'ChannelModelEffect',
  );
  _writeTransitionResult(
    out,
    resultName: 'PushTransitionResult',
    actionName: 'PushModelAction',
    stateName: 'PushModelState',
    effectName: 'PushModelEffect',
  );
  _writeVocabulary(out, manifest);
  return out.toString();
}

void _writeDartEnum(StringBuffer out, String name, List<String> values) {
  out.writeln('enum $name {');
  for (final value in values) {
    out.writeln("  ${_dartIdentifier(value)}('$value'),");
  }
  out
    ..writeln('  ;')
    ..writeln()
    ..writeln('  const $name(this.wireName);')
    ..writeln()
    ..writeln('  final String wireName;')
    ..writeln()
    ..writeln('  static $name fromWire(String value) => switch (value) {');
  for (final value in values) {
    out.writeln("    '$value' => $name.${_dartIdentifier(value)},");
  }
  out
    ..writeln("    _ => throw FormatException('Unknown $name: \$value'),")
    ..writeln('  };')
    ..writeln('}')
    ..writeln();
}

void _writeDartRecord(
  StringBuffer out,
  String className,
  Map<String, String> fields,
) {
  out
    ..writeln('final class $className {')
    ..writeln('  const $className({');
  for (final entry in fields.entries) {
    out.writeln('    required this.${entry.key},');
  }
  out
    ..writeln('  });')
    ..writeln();
  for (final entry in fields.entries) {
    out.writeln('  final ${_dartType(entry.value)} ${entry.key};');
  }
  out
    ..writeln()
    ..writeln('  factory $className.fromJson(Map<String, Object?> json) =>')
    ..writeln('      $className(');
  for (final entry in fields.entries) {
    final jsonExpression = _fromJsonExpression(
      "json['${entry.key}']",
      entry.value,
    );
    out.writeln(
      '        ${entry.key}: $jsonExpression,',
    );
  }
  out
    ..writeln('      );')
    ..writeln()
    ..writeln('  Map<String, Object?> toJson() => {');
  for (final entry in fields.entries) {
    final jsonExpression = _toJsonExpression(entry.key, entry.value);
    out.writeln("    '${entry.key}': $jsonExpression,");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  $className copyWith({');
  for (final entry in fields.entries) {
    out.writeln('    ${_dartType(entry.value)}? ${entry.key},');
  }
  out
    ..writeln('  }) =>')
    ..writeln('      $className(');
  for (final entry in fields.entries) {
    out.writeln('        ${entry.key}: ${entry.key} ?? this.${entry.key},');
  }
  out
    ..writeln('      );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  bool operator ==(Object other) =>')
    ..writeln('      identical(this, other) ||')
    ..writeln('      other is $className &&');
  var index = 0;
  for (final entry in fields.entries) {
    index++;
    final suffix = index == fields.length ? ';' : ' &&';
    out.writeln('      ${entry.key} == other.${entry.key}$suffix');
  }
  out
    ..writeln()
    ..writeln('  @override')
    ..writeln('  int get hashCode => Object.hashAll([');
  for (final name in fields.keys) {
    out.writeln('    $name,');
  }
  out
    ..writeln('  ]);')
    ..writeln()
    ..writeln('  @override')
    ..writeln("  String toString() => '$className(\${toJson()})';")
    ..writeln('}')
    ..writeln();
}

void _writeDartUnion({
  required StringBuffer out,
  required String className,
  required String enumName,
  required Map<String, Map<String, String>> variants,
}) {
  final payloadFields = <String, String>{};
  for (final fields in variants.values) {
    for (final entry in fields.entries) {
      final previous = payloadFields[entry.key];
      if (previous != null && previous != entry.value) {
        throw FormatException(
          'Payload field ${entry.key} has conflicting types: '
          '$previous and ${entry.value}',
        );
      }
      payloadFields[entry.key] = entry.value;
    }
  }

  out
    ..writeln('final class $className {')
    ..writeln('  const $className._({')
    ..writeln('    required this.kind,');
  for (final entry in payloadFields.entries) {
    out.writeln('    this.${entry.key},');
  }
  out
    ..writeln('  });')
    ..writeln();

  for (final variant in variants.entries) {
    final factoryName = _lowerFirst(variant.key);
    out.write('  factory $className.$factoryName(');
    if (variant.value.isEmpty) {
      out.writeln(') =>');
    } else {
      out.writeln('{');
      for (final field in variant.value.entries) {
        out.writeln('    required ${_dartType(field.value)} ${field.key},');
      }
      out.writeln('  }) =>');
    }
    out
      ..writeln('      $className._(')
      ..writeln('        kind: $enumName.${_dartIdentifier(variant.key)},');
    for (final field in variant.value.keys) {
      out.writeln('        $field: $field,');
    }
    out
      ..writeln('      );')
      ..writeln();
  }

  out.writeln('  final $enumName kind;');
  for (final entry in payloadFields.entries) {
    out.writeln('  final ${_dartType(entry.value)}? ${entry.key};');
  }
  out
    ..writeln()
    ..writeln('  factory $className.fromJson(Map<String, Object?> json) {')
    ..writeln(
      "    final kind = $enumName.fromWire(json['kind']! as String);",
    )
    ..writeln('    return switch (kind) {');
  for (final variant in variants.entries) {
    final enumValue = _dartIdentifier(variant.key);
    final factoryName = _lowerFirst(variant.key);
    out.write('      $enumName.$enumValue => $className.$factoryName(');
    if (variant.value.isEmpty) {
      out.writeln('),');
    } else {
      out.writeln();
      for (final field in variant.value.entries) {
        final jsonExpression = _fromJsonExpression(
          "json['${field.key}']",
          field.value,
        );
        out.writeln(
          '        ${field.key}: $jsonExpression,',
        );
      }
      out.writeln('      ),');
    }
  }
  out
    ..writeln('    };')
    ..writeln('  }')
    ..writeln()
    ..writeln('  Map<String, Object?> toJson() => {')
    ..writeln("    'kind': kind.wireName,");
  for (final entry in payloadFields.entries) {
    final jsonExpression = _nullableToJsonExpression(
      entry.key,
      entry.value,
    );
    out.writeln(
      "    if (${entry.key} != null) '${entry.key}': $jsonExpression,",
    );
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  bool operator ==(Object other) =>')
    ..writeln('      identical(this, other) ||')
    ..writeln('      other is $className &&')
    ..writeln('      kind == other.kind &&');
  var index = 0;
  for (final name in payloadFields.keys) {
    index++;
    final suffix = index == payloadFields.length ? ';' : ' &&';
    out.writeln('      $name == other.$name$suffix');
  }
  out
    ..writeln()
    ..writeln('  @override')
    ..writeln('  int get hashCode => Object.hashAll([')
    ..writeln('    kind,');
  for (final name in payloadFields.keys) {
    out.writeln('    $name,');
  }
  out
    ..writeln('  ]);')
    ..writeln()
    ..writeln('  @override')
    ..writeln("  String toString() => '$className(\${toJson()})';")
    ..writeln('}')
    ..writeln();
}

void _writeTransitionResult(
  StringBuffer out, {
  required String resultName,
  required String actionName,
  required String stateName,
  required String effectName,
}) {
  out
    ..writeln('final class $resultName {')
    ..writeln('  $resultName({')
    ..writeln('    required this.disposition,')
    ..writeln('    required this.action,')
    ..writeln('    required this.postState,')
    ..writeln('    required List<$effectName> effects,')
    ..writeln('  }) : effects = List.unmodifiable(effects);')
    ..writeln()
    ..writeln('  final TransitionDisposition disposition;')
    ..writeln('  final $actionName action;')
    ..writeln('  final $stateName postState;')
    ..writeln('  final List<$effectName> effects;')
    ..writeln()
    ..writeln('  Map<String, Object?> toJson() => {')
    ..writeln("    'disposition': disposition.wireName,")
    ..writeln("    'action': action.wireName,")
    ..writeln("    'postState': postState.toJson(),")
    ..writeln(
      "    'effects': effects.map((effect) => effect.toJson()).toList(),",
    )
    ..writeln('  };')
    ..writeln('}')
    ..writeln();
}

void _writeVocabulary(StringBuffer out, Manifest manifest) {
  out
    ..writeln('abstract final class RealtimeFormalVocabulary {')
    ..writeln('  static const stateFields = <String>{');
  for (final name in manifest.records['SocketModelState']!.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const eventKinds = <String>{');
  for (final name in manifest.events.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const actionIds = <String>{');
  for (final name in manifest.actions.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const effectKinds = <String>{');
  for (final name in manifest.effects.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const channelEventKinds = <String>{');
  for (final name in manifest.channelEvents.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const channelActionIds = <String>{');
  for (final name in manifest.channelActions.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const channelEffectKinds = <String>{');
  for (final name in manifest.channelEffects.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const pushEventKinds = <String>{');
  for (final name in manifest.pushEvents.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const pushActionIds = <String>{');
  for (final name in manifest.pushActions.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const pushEffectKinds = <String>{');
  for (final name in manifest.pushEffects.keys) {
    out.writeln("    '$name',");
  }
  out
    ..writeln('  };')
    ..writeln('}')
    ..writeln();
}

String _formatDart(String source) {
  final directory = Directory.systemTemp.createTempSync('realtime_schema_');
  try {
    final file = File('${directory.path}/model_schema.dart')
      ..writeAsStringSync(source);
    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['format', '--line-length=80', file.path],
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        Platform.resolvedExecutable,
        ['format', file.path],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    return file.readAsStringSync();
  } finally {
    directory.deleteSync(recursive: true);
  }
}

String _dartType(String manifestType) {
  if (manifestType == 'bool') return 'bool';
  if (manifestType == 'int') return 'int';
  if (manifestType.startsWith('enum:')) return manifestType.substring(5);
  if (manifestType.startsWith('record:')) return manifestType.substring(7);
  throw FormatException('Unknown manifest type: $manifestType');
}

String _fromJsonExpression(String expression, String manifestType) {
  if (manifestType == 'bool') return '$expression! as bool';
  if (manifestType == 'int') return '($expression! as num).toInt()';
  if (manifestType.startsWith('enum:')) {
    final type = manifestType.substring(5);
    return '$type.fromWire($expression! as String)';
  }
  if (manifestType.startsWith('record:')) {
    final type = manifestType.substring(7);
    return '$type.fromJson(($expression! as Map).cast<String, Object?>())';
  }
  throw FormatException('Unknown manifest type: $manifestType');
}

String _toJsonExpression(String field, String manifestType) {
  if (manifestType == 'bool' || manifestType == 'int') return field;
  if (manifestType.startsWith('enum:')) return '$field.wireName';
  if (manifestType.startsWith('record:')) return '$field.toJson()';
  throw FormatException('Unknown manifest type: $manifestType');
}

String _nullableToJsonExpression(String field, String manifestType) {
  if (manifestType == 'bool' || manifestType == 'int') return field;
  if (manifestType.startsWith('enum:')) return '$field!.wireName';
  if (manifestType.startsWith('record:')) return '$field!.toJson()';
  throw FormatException('Unknown manifest type: $manifestType');
}

String _dartIdentifier(String wireName) {
  final candidate = _lowerFirst(wireName).replaceAll(
    RegExp('[^A-Za-z0-9_]'),
    '_',
  );
  if (_dartReservedWords.contains(candidate)) {
    return '${candidate}Value';
  }
  return candidate;
}

String _lowerFirst(String value) =>
    value.isEmpty ? value : '${value[0].toLowerCase()}${value.substring(1)}';

String _tlaString(String value) => '"${value.replaceAll('"', '\\"')}"';

final class Manifest {
  Manifest({
    required this.schemaVersion,
    required this.enums,
    required this.records,
    required this.events,
    required this.actions,
    required this.effects,
    required this.channelEvents,
    required this.channelActions,
    required this.channelEffects,
    required this.pushEvents,
    required this.pushActions,
    required this.pushEffects,
    required this.traceRequiredFields,
    required this.traceIdentityFields,
  });

  factory Manifest.parse(Map<String, Object?> json) {
    Map<String, List<String>> parseEnums(Object? value) =>
        (value! as Map<String, Object?>).map(
          (key, values) => MapEntry(
            key,
            (values! as List<Object?>).cast<String>(),
          ),
        );

    Map<String, Map<String, String>> parseShapes(Object? value) =>
        (value! as Map<String, Object?>).map(
          (key, fields) => MapEntry(
            key,
            (fields! as Map<String, Object?>).cast<String, String>(),
          ),
        );

    final trace = json['trace']! as Map<String, Object?>;
    final manifest = Manifest(
      schemaVersion: (json['schemaVersion']! as num).toInt(),
      enums: parseEnums(json['enums']),
      records: parseShapes(json['records']),
      events: parseShapes(json['events']),
      actions: (json['actions']! as Map<String, Object?>)
          .cast<String, String>(),
      effects: parseShapes(json['effects']),
      channelEvents: parseShapes(json['channelEvents']),
      channelActions: (json['channelActions']! as Map<String, Object?>)
          .cast<String, String>(),
      channelEffects: parseShapes(json['channelEffects']),
      pushEvents: parseShapes(json['pushEvents']),
      pushActions: (json['pushActions']! as Map<String, Object?>)
          .cast<String, String>(),
      pushEffects: parseShapes(json['pushEffects']),
      traceRequiredFields: (trace['requiredFields']! as List<Object?>)
          .cast<String>(),
      traceIdentityFields: (trace['identityFields']! as List<Object?>)
          .cast<String>(),
    );
    manifest.validate();
    return manifest;
  }

  final int schemaVersion;
  final Map<String, List<String>> enums;
  final Map<String, Map<String, String>> records;
  final Map<String, Map<String, String>> events;
  final Map<String, String> actions;
  final Map<String, Map<String, String>> effects;
  final Map<String, Map<String, String>> channelEvents;
  final Map<String, String> channelActions;
  final Map<String, Map<String, String>> channelEffects;
  final Map<String, Map<String, String>> pushEvents;
  final Map<String, String> pushActions;
  final Map<String, Map<String, String>> pushEffects;
  final List<String> traceRequiredFields;
  final List<String> traceIdentityFields;

  void validate() {
    if (schemaVersion < 1) {
      throw const FormatException('schemaVersion must be positive');
    }
    if (!records.containsKey('SocketModelState')) {
      throw const FormatException('SocketModelState record is required');
    }
    if (events.isEmpty ||
        actions.isEmpty ||
        effects.isEmpty ||
        channelEvents.isEmpty ||
        channelActions.isEmpty ||
        channelEffects.isEmpty ||
        pushEvents.isEmpty ||
        pushActions.isEmpty ||
        pushEffects.isEmpty) {
      throw const FormatException(
        'Every machine requires events, actions, and effects',
      );
    }
    final allNames = <String>{};
    for (final name in [
      ...enums.keys,
      ...records.keys,
      ...events.keys,
      ...actions.keys,
      ...effects.keys,
      ...channelEvents.keys,
      ...channelActions.keys,
      ...channelEffects.keys,
      ...pushEvents.keys,
      ...pushActions.keys,
      ...pushEffects.keys,
    ]) {
      if (!allNames.add(name)) {
        throw FormatException('Duplicate manifest name: $name');
      }
    }
    final shapes = [
      ...records.values,
      ...events.values,
      ...effects.values,
      ...channelEvents.values,
      ...channelEffects.values,
      ...pushEvents.values,
      ...pushEffects.values,
    ];
    for (final fields in shapes) {
      for (final type in fields.values) {
        if (type == 'bool' || type == 'int') continue;
        if (type.startsWith('enum:') && enums.containsKey(type.substring(5))) {
          continue;
        }
        if (type.startsWith('record:') &&
            records.containsKey(type.substring(7))) {
          continue;
        }
        throw FormatException('Unknown field type: $type');
      }
    }
  }
}
