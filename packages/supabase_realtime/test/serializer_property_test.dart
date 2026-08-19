import 'package:collection/collection.dart';
import 'package:supabase_realtime/src/serializer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'text-frame encode/decode is identity across the finite frame domain',
    () {
      const serializer = Serializer();
      const equality = DeepCollectionEquality();
      const refs = <String?>[null, '', '1', 'ref-µ'];
      const topics = ['', 'phoenix', 'realtime:room-😀'];
      const events = ['phx_join', 'heartbeat', 'custom-ß'];
      final payloads = <Object?>[
        null,
        <String, Object?>{},
        {
          'ok': true,
          'count': 3,
          'nested': <Object?>['x', null],
        },
        <Object?>[1, 'two', false],
        'scalar',
      ];

      var cases = 0;
      for (final joinRef in refs) {
        for (final ref in refs) {
          for (final topic in topics) {
            for (final event in events) {
              for (final payload in payloads) {
                final message = <String, dynamic>{
                  'join_ref': joinRef,
                  'ref': ref,
                  'topic': topic,
                  'event': event,
                  'payload': payload,
                };
                final decoded = serializer.decode(serializer.encode(message));
                expect(equality.equals(decoded, message), isTrue);
                cases++;
              }
            }
          }
        }
      }
      expect(cases, 720);
    },
  );
}
