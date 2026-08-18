import 'dart:convert';

import 'package:supabase_realtime/src/realtime_presence.dart';
import 'package:test/test.dart';

void main() {
  group('RealtimePresence.syncState', () {
    test('does not mutate the server payload in place', () {
      // _transformState used to rewrite phx_ref -> presence_ref and remove
      // phx_ref / phx_ref_prev directly on the caller's Map. Anything else
      // holding a reference to that payload (e.g. a raw 'message' listener
      // on the socket) would see the corrupted, JS-private shape.
      final input = <String, dynamic>{
        'user-1': {
          'metas': [
            {'phx_ref': 'ref-1', 'user_id': 1},
            {'phx_ref': 'ref-2', 'phx_ref_prev': 'ref-1', 'user_id': 1},
          ],
        },
      };
      final snapshot = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;

      RealtimePresence.syncState({}, input);

      expect(
        input,
        equals(snapshot),
        reason:
            "syncState must not rewrite phx_ref -> presence_ref on the "
            "caller's map",
      );
    });

    test('syncing the same payload twice does not crash', () {
      // Second pass used to throw `Null is not a subtype of String` because
      // the first pass had already stripped phx_ref from the meta map.
      final input = <String, dynamic>{
        'user-1': {
          'metas': [
            {'phx_ref': 'ref-1', 'user_id': 1},
          ],
        },
      };

      RealtimePresence.syncState({}, input);
      expect(
        () => RealtimePresence.syncState({}, input),
        returnsNormally,
      );
    });

    test('produces Presence objects with presence_ref populated', () {
      final input = <String, dynamic>{
        'user-1': {
          'metas': [
            {'phx_ref': 'ref-1', 'user_id': 1},
          ],
        },
      };

      final state = RealtimePresence.syncState({}, input);
      expect(state['user-1'], hasLength(1));
      expect(state['user-1']!.first.presenceReference, equals('ref-1'));
    });
  });
}
