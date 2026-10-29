import 'package:realtime_client/realtime_client.dart';
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

      expect(client.conn, isNull);
      expect(
        client.connState,
        SocketStates.closed,
        reason:
            'connState must recover after transport throws before a '
            'connection is assigned',
      );
    },
  );
}
