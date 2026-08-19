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

import 'dart:async';

import 'package:supabase_realtime/supabase_realtime.dart';
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
          reconnectAfter: (_) => const Duration(milliseconds: 20),
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
      'a user disconnect racing the throw does not schedule a retry',
      () async {
        // The field scenario: the user taps sign-out just as a resume-
        // triggered connect attempt is starting, so the disconnect lands
        // between the connect commit and the transport throw.
        //
        // This used to be simulated by assigning `connectionState =
        // disconnecting` from inside transport(), because the shell had no
        // other way to express it. That made a derived, deprecated view
        // authoritative over lifecycle intent. The race is now expressed
        // directly: a real disconnect() issued at exactly that moment. Its
        // event is queued behind the in-flight batch and processed ahead of
        // the transport failure, so intent is already down when the failure
        // is handled and no retry may be armed (ADR-013 S1).
        var transportCallCount = 0;
        final socketHolder = <RealtimeClient>[];
        final socket = RealtimeClient(
          socketEndpoint,
          reconnectAfter: (_) => const Duration(milliseconds: 20),
          transport: (_, _) {
            transportCallCount++;
            unawaited(socketHolder.single.disconnect());
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
              'A user disconnect that races the transport throw must win: '
              'arming a retry here would fight the disconnect intent.',
        );
        expect(socket.connectionState, SocketState.disconnected);
      },
    );
  });
}
