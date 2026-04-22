import 'dart:async';
import 'dart:io';

import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Regression test for the flat-retry-cadence bug (field repro: wifi off →
/// infinite 1-second retries with no backoff progression).
///
/// The realtime client's reconnect timer callback used to call
/// `disconnect()` before `connect()`. In concert with
/// `fix/disconnect-leak-reconnect-timer` (which made `disconnect()`
/// unconditionally reset the retry timer to cancel leaked reconnects after
/// `removeChannel()`), this zeroed `_tries` on every retry tick, so
/// `scheduleTimeout()` always computed the next delay as
/// `reconnectAfterMs(1) = firstDelay`. Exponential backoff never kicked in.
///
/// Fix: the retry callback clears `conn` directly instead of going through
/// `disconnect()`, preserving `_tries` across failures.
///
/// Assertion strategy: we install a transport that throws synchronously on
/// every call, drive several retry ticks with a tiny first-delay (so the
/// whole test finishes in ~400ms), and verify the gap between consecutive
/// transport() invocations grows. With the bug, all gaps are equal
/// (~firstDelay). With the fix, gaps roughly double.
void main() {
  // Bind then close a local port to guarantee nothing will listen there
  // for the duration of the test. Every connect() attempt to this port
  // rejects with ECONNREFUSED via the WebSocketChannel's `.ready` future,
  // exercising the realtime client's inner-catch retry path. This is more
  // portable than using a hardcoded reserved port (e.g. 1) which may be
  // firewalled or behave differently across CI environments.
  late int refusedPort;

  setUp(() async {
    final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    refusedPort = tmp.port;
    await tmp.close();
  });

  test('retry callback preserves _tries so backoff grows across failures',
      () async {
    final callTimesMs = <int>[];
    final start = DateTime.now();

    final client = RealtimeClient(
      'ws://127.0.0.1:$refusedPort/realtime/v1',
      transport: (url, headers) {
        callTimesMs.add(DateTime.now().difference(start).inMilliseconds);
        // Real IOWebSocketChannel against a guaranteed-closed port. The
        // returned channel's `.ready` rejects asynchronously with a
        // connection-refused error, funnelling into the inner catch in
        // RealtimeClient.connect() — the same path production hits when
        // DNS resolution succeeds but the server is unreachable (e.g.
        // wifi off, server down, cloud region outage).
        return IOWebSocketChannel.connect(Uri.parse(url));
      },
      // Slightly larger first delay than the retry-timer minimum to give
      // `.ready` enough time to reject before the timer fires. With the
      // fix, expected gaps are ~25, 50, 100, 200 ms. With the bug, all
      // gaps are ~25 ms.
      reconnectAfterMs: (tries) => 25 << (tries - 1),
    );

    // ignore: invalid_use_of_internal_member
    unawaited(client.connect());

    // Time budget for 5 calls with growing gaps: 25+50+100+200+400 =
    // 775ms. 1000ms gives slack for scheduling jitter and `.ready`
    // resolution latency (ECONNREFUSED on loopback is typically sub-ms
    // but GC/scheduler can add tens of ms).
    await Future.delayed(const Duration(milliseconds: 1000));

    // Stop the retry loop to avoid interfering with other tests.
    await client.disconnect();

    expect(
      callTimesMs.length,
      greaterThanOrEqualTo(5),
      reason: 'Expected at least 5 connect attempts in the 450ms budget; '
          'saw ${callTimesMs.length}. Either transport is not being invoked '
          'from the retry callback, or scheduling is radically slower than '
          'expected.',
    );

    final gaps = <int>[
      for (int i = 1; i < callTimesMs.length; i++)
        callTimesMs[i] - callTimesMs[i - 1],
    ];

    // The key assertion: successive gaps must grow, otherwise `_tries`
    // isn't climbing and backoff isn't real. We check that each of the
    // first 3 transitions is strictly increasing by a non-trivial margin
    // (5ms, well below the 10ms→20ms→40ms→80ms target growth but above
    // typical scheduler jitter).
    //
    // With the bug, every gap is ~10ms and these assertions all fail.
    expect(
      gaps.length,
      greaterThanOrEqualTo(4),
      reason: 'Need at least 4 gaps (5 calls) to observe backoff growth; '
          'saw ${gaps.length} gaps from ${callTimesMs.length} calls.',
    );
    expect(
      gaps[1],
      greaterThan(gaps[0] + 10),
      reason: 'gap[1] (expected ~50ms) should exceed gap[0] (~25ms) by a '
          'clear margin. Actual gaps: $gaps. Flat gaps indicate _tries '
          'is being reset to 0 between retries.',
    );
    expect(
      gaps[2],
      greaterThan(gaps[1] + 20),
      reason: 'gap[2] (expected ~100ms) should exceed gap[1] (~50ms). '
          'Actual gaps: $gaps.',
    );
    expect(
      gaps[3],
      greaterThan(gaps[2] + 40),
      reason: 'gap[3] (expected ~200ms) should exceed gap[2] (~100ms). '
          'Actual gaps: $gaps.',
    );
  });
}
