// Tests for heartbeat behavior that spans the socket-session lifecycle.
//
// Kept in its own file (rather than appended to socket_test.dart's
// `sendHeartbeat` group) so it doesn't conflict with other fix branches that
// also add tests at the end of that group.

import 'package:mocktail/mocktail.dart';
import 'package:realtime_client/realtime_client.dart';
import 'package:realtime_client/src/constants.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockIOWebSocketChannel extends Mock implements IOWebSocketChannel {}

class _MockWebSocketSink extends Mock implements WebSocketSink {}

void main() {
  const socketEndpoint = 'wss://localhost:0/';

  test(
      'fresh reconnect after an unacked heartbeat does not immediately '
      'self-close', () async {
    // pendingHeartbeatRef is only cleared when (a) the matching reply arrives
    // in onConnMessage, or (b) sendHeartbeat sees it non-null and treats it
    // as a heartbeat timeout (closing the socket). No lifecycle hook clears
    // it, so if the socket closes (server drop or otherwise) with an
    // in-flight heartbeat, the ref leaks across the reconnect into the new
    // session and the very next heartbeat tick closes the brand-new socket.
    //
    // User-visible symptom: repeated immediate post-reconnect drops on a
    // flaky network.
    final sinks = <_MockWebSocketSink>[];

    _MockIOWebSocketChannel makeChannel() {
      final c = _MockIOWebSocketChannel();
      final s = _MockWebSocketSink();
      sinks.add(s);
      when(() => c.sink).thenReturn(s);
      when(() => c.ready).thenAnswer((_) => Future.value());
      when(() => s.add(any())).thenAnswer((_) {});
      when(() => s.close(any(), any())).thenAnswer((_) => Future.value());
      when(() => s.close()).thenAnswer((_) => Future.value());
      return c;
    }

    final socket = RealtimeClient(
      socketEndpoint,
      transport: (_, __) => makeChannel(),
    );

    // First session: send a heartbeat and leave it unacked.
    await socket.connect();
    socket.connState = SocketStates.open;
    await socket.sendHeartbeat();
    expect(socket.pendingHeartbeatRef, isNotNull,
        reason: 'sanity: first heartbeat recorded');

    // Session ends before the reply arrives.
    await socket.disconnect();

    // Fresh session.
    await socket.connect();
    socket.connState = SocketStates.open;

    // Next heartbeat tick on the new session.
    await socket.sendHeartbeat();

    // The second mock is the fresh session's sink; it must NOT have been
    // closed with the heartbeat-timeout reason.
    verifyNever(
      () => sinks[1].close(Constants.wsCloseNormal, 'heartbeat timeout'),
    );
    expect(socket.connState, SocketStates.open,
        reason:
            'a stale pendingHeartbeatRef from a previous session must not '
            'kill the fresh socket on its first heartbeat tick');
  });
}
