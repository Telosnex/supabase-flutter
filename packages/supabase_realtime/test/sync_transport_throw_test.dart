import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:test/test.dart';

void main() {
  test(
    'synchronous transport throw does not leave connection state connecting',
    () async {
      final client = RealtimeClient(
        'wss://localhost:0/',
        transport: (_, _) => throw StateError('synchronous transport failure'),
      );

      await client.connect();

      expect(client.connection, isNull);
      expect(
        client.connectionState,
        SocketState.closed,
        reason:
            'connectionState must recover after transport throws before a '
            'connection is assigned',
      );
    },
  );
}
