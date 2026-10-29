// Regression test for `RealtimeClient.connect()`'s *outer* catch scheduling
// a reconnect on synchronous throws from transport().
//
// Background: the inner `await localConn.ready` catch calls
// `reconnectTimer.scheduleTimeout()` on failure. The outer catch
// (covering synchronous throws from transport() or anything else before
// the .ready await) did not. Result: a synchronous failure path surfaced
// the error via `_onConnError` but never armed a retry, leaving the
// socket wedged until a later explicit connect().
//
// Observed symptom in the field on iOS app resume after long background
// suspension: `WebSocketChannelException: HandshakeException: Connection
// terminated during handshake` fires once per channel during the
// resume-triggered connect(), then silence — no reconnect attempts, no
// recovery short of relaunching the app.
//
// Lives in its own file rather than `socket_test.dart` to keep the
// tail-of-file merge surface clean relative to sibling fix branches that
// touch `socket_test.dart` — precedent: `b8085ff Revert union-merge
// attempt; move conflicting test to its own file instead`.

import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main() {
  const socketEndpoint = 'wss://example.com/realtime/v1';

  group('connect outer catch reconnect scheduling', () {
    test(
      'schedules a retry after a synchronous throw from transport()',
      () async {
        var transportCallCount = 0;
        final socket = RealtimeClient(
          socketEndpoint,
          // Tight backoff so the test finishes quickly; 20 ms flat.
          reconnectAfterMs: (_) => 20,
          transport: (_, _) {
            transportCallCount++;
            // Always throw synchronously — we're verifying that the retry
            // loop fires regardless, not that it succeeds.
            throw StateError(
              'synchronous transport failure (attempt $transportCallCount)',
            );
          },
        );

        // First connect(): outer catch runs, _onConnError fires, and (with
        // the fix) reconnectTimer.scheduleTimeout() arms the retry.
        await socket.connect();
        expect(
          transportCallCount,
          1,
          reason: 'sanity: connect() called transport() exactly once',
        );

        // Wait long enough for several backoff intervals. With the fix,
        // the reconnect loop fires every ~20 ms; without the fix, the
        // timer is never scheduled and transport() is never called again.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          transportCallCount,
          greaterThan(1),
          reason:
              'reconnectTimer must fire and retry connect() after an outer-'
              'catch failure. Only $transportCallCount attempts observed '
              'over 200 ms with 20 ms backoff — the retry timer was never '
              'armed.',
        );

        await socket.disconnect();
        final callsAfterDisconnect = transportCallCount;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(
          transportCallCount,
          callsAfterDisconnect,
          reason:
              'disconnect must cancel retries even when transport threw '
              'before assigning a connection',
        );
      },
    );

    test(
      'respects a disconnecting connState and does not schedule a retry',
      () async {
        // The inner `await localConn.ready` catch guards against fighting a
        // concurrent user-initiated disconnect by checking
        // `connState != disconnected && connState != disconnecting`. The
        // outer catch needs the same guard. Prove it by flipping connState
        // to `disconnecting` *inside* transport() (simulating: user tapped
        // sign-out just as the resume-triggered connect attempt was
        // starting, landing after connect()'s `connState = connecting`
        // line but before the throw propagates to the outer catch) and
        // confirming that no retries fire.
        var transportCallCount = 0;
        final socketHolder = <RealtimeClient>[];
        final socket = RealtimeClient(
          socketEndpoint,
          reconnectAfterMs: (_) => 20,
          transport: (_, _) {
            transportCallCount++;
            socketHolder.single.connState = SocketStates.disconnecting;
            throw StateError('synchronous transport failure');
          },
        );
        socketHolder.add(socket);

        await socket.connect();
        expect(transportCallCount, 1);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          transportCallCount,
          1,
          reason:
              'When connState is disconnecting at the time of the throw, '
              'the outer catch must not schedule a retry — that would '
              "fight the user's disconnect intent.",
        );
      },
    );
  });
}
