import 'dart:convert';

/// Parser for the deliberately restricted TLC value syntax emitted by `-dump`.
///
/// It accepts integers, strings, booleans, records, and sequences. Formal
/// tooling rejects every other TLA+ value rather than guessing.
final class TlaValueParser {
  TlaValueParser(this.source);

  final String source;
  var _offset = 0;

  Map<String, Object?> parseAssignments() {
    final assignments = <String, Object?>{};
    _skipWhitespace();
    while (!_atEnd) {
      _expect(r'/\');
      _skipWhitespace();
      final name = _identifier();
      _skipWhitespace();
      _expect('=');
      final value = _value();
      if (assignments.containsKey(name)) {
        throw FormatException('Duplicate assignment $name', source, _offset);
      }
      assignments[name] = value;
      _skipWhitespace();
    }
    return assignments;
  }

  Object? _value() {
    _skipWhitespace();
    if (_startsWith('<<')) return _sequence();
    if (_startsWith('[')) return _record();
    if (_startsWith('"')) return _string();
    if (_startsWith('TRUE')) {
      _offset += 4;
      return true;
    }
    if (_startsWith('FALSE')) {
      _offset += 5;
      return false;
    }
    if (_startsWith('-') || _isDigit(_peek)) return _integer();
    throw FormatException('Unsupported TLC value', source, _offset);
  }

  Map<String, Object?> _record() {
    _expect('[');
    final result = <String, Object?>{};
    _skipWhitespace();
    if (_startsWith(']')) {
      _offset++;
      return result;
    }
    while (true) {
      final key = _identifier();
      _skipWhitespace();
      _expect('|->');
      final value = _value();
      if (result.containsKey(key)) {
        throw FormatException('Duplicate record key $key', source, _offset);
      }
      result[key] = value;
      _skipWhitespace();
      if (_startsWith(']')) {
        _offset++;
        return result;
      }
      _expect(',');
      _skipWhitespace();
    }
  }

  List<Object?> _sequence() {
    _expect('<<');
    final result = <Object?>[];
    _skipWhitespace();
    if (_startsWith('>>')) {
      _offset += 2;
      return result;
    }
    while (true) {
      result.add(_value());
      _skipWhitespace();
      if (_startsWith('>>')) {
        _offset += 2;
        return result;
      }
      _expect(',');
      _skipWhitespace();
    }
  }

  String _string() {
    final start = _offset;
    _offset++;
    var escaped = false;
    while (!_atEnd) {
      final char = source[_offset++];
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        return jsonDecode(source.substring(start, _offset)) as String;
      }
    }
    throw FormatException('Unterminated string', source, start);
  }

  int _integer() {
    final start = _offset;
    if (_startsWith('-')) _offset++;
    while (!_atEnd && _isDigit(_peek)) {
      _offset++;
    }
    return int.parse(source.substring(start, _offset));
  }

  String _identifier() {
    _skipWhitespace();
    final start = _offset;
    while (!_atEnd && RegExp(r'[A-Za-z0-9_]').hasMatch(_peek)) {
      _offset++;
    }
    if (start == _offset) {
      throw FormatException('Expected identifier', source, _offset);
    }
    return source.substring(start, _offset);
  }

  void _expect(String token) {
    if (!_startsWith(token)) {
      throw FormatException('Expected $token', source, _offset);
    }
    _offset += token.length;
  }

  void _skipWhitespace() {
    while (!_atEnd && _peek.trim().isEmpty) {
      _offset++;
    }
  }

  bool _startsWith(String value) => source.startsWith(value, _offset);
  bool _isDigit(String value) =>
      value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;
  bool get _atEnd => _offset >= source.length;
  String get _peek => source[_offset];
}

Iterable<Map<String, Object?>> parseTlcDump(String source) sync* {
  final matches = RegExp(
    r'^State [0-9]+:\n',
    multiLine: true,
  ).allMatches(source);
  final list = matches.toList(growable: false);
  for (var index = 0; index < list.length; index++) {
    final start = list[index].end;
    final end = index + 1 < list.length ? list[index + 1].start : source.length;
    yield TlaValueParser(source.substring(start, end)).parseAssignments();
  }
}

String encodeTlaValue(Object? value) {
  if (value is bool) return value ? 'TRUE' : 'FALSE';
  if (value is int) return '$value';
  if (value is String) return jsonEncode(value);
  if (value is List<Object?>) {
    return '<<${value.map(encodeTlaValue).join(', ')}>>';
  }
  if (value is Map) {
    final entries = value.entries
        .map((entry) => '${entry.key} |-> ${encodeTlaValue(entry.value)}')
        .join(', ');
    return '[$entries]';
  }
  throw FormatException('Cannot encode ${value.runtimeType} as a TLA+ value');
}
