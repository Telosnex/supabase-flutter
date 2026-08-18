// Regression tests for `RealtimeChannel.rejoinUntilConnected()`.
//
// Background: the channel's `_rejoinTimer` fires `rejoinUntilConnected()`
// which in turn calls `rejoin()` whenever the socket is connected. The
// pre-fix implementation called `_rejoinTimer.scheduleTimeout()`
// unconditionally at the top of the method, so after one scheduling the
// timer would keep firing on every backoff interval regardless of the
// outcome of each rejoin attempt. When the server took longer than one
// backoff to reply (very common — first retry delay is 1s, next is 2s),
// a second tick would call `rejoin()` while the first attempt was still
// in `ChannelStates.joining`. Inside `rejoin()`,
// `socket.leaveOpenTopic(topic)` then finds *this* channel as the
// duplicate, calls `unsubscribe()` on it, and silently destroys the
// channel mid-flight.
//
// The canonical Phoenix JS client does not auto-reschedule (its timer
// callback is literally `() => { if(isConnected) rejoin() }`). Modern
// supabase-js uses @supabase/phoenix and inherits that behaviour. The
// fix brings Dart in line: only re-arm the timer when the socket is
// down (in which case `rejoin()` couldn't be attempted); otherwise let
// the downstream ok/error/timeout handlers decide whether another
// retry is needed.
//
// Lives in its own file rather than `channel_test.dart` to avoid
// tail-of-file merge conflicts when this branch stacks with other
// fix/* branches off upstream/main — precedent: `b8085ff Revert
// union-merge attempt; move conflicting test to its own file instead`.

import 'dart:async';

import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:supabase_realtime/src/constants.dart';
import 'package:supabase_realtime/src/message.dart';
import 'package:test/test.dart';

void main() {
  group('rejoinUntilConnected auto-reschedule', () {
    test(
      'a single phx_timeout does not cascade into unbounded retries',
      () async {
        // Very fast backoff so the test runs quickly: 50 ms flat.
        final pushSocket = _PushCountingSocket(
          'wss://example.com/socket',
          reconnectAfter: (_) => const Duration(milliseconds: 50),
        );
        final ch = pushSocket.channel('room:rejoin-timer-test');
        ch.subscribe();

        // subscribe() sends one phx_join.
        expect(
          pushSocket.joinPushCount,
          1,
          reason: 'sanity: subscribe() sends the initial phx_join',
        );

        // Simulate the joinPush timing out waiting for a server reply.
        // This fires the constructor-level `joinPush.receive('timeout', …)`
        // hook which transitions state to errored and calls
        // `_rejoinTimer.scheduleTimeout()` — exactly ONE retry schedule.
        // (Using 'timeout' rather than 'error' keeps this test independent
        // of any joinPush('error') handlers added by sibling fix branches,
        // since we fork from upstream/main.)
        // ignore: invalid_use_of_internal_member
        ch.joinPush.trigger('timeout', {});

        // The server never replies to the subsequent retry(s) we trigger,
        // so no new scheduleTimeout() should happen until joinPush's own
        // default 10s timeout — well outside this test window.
        //
        // With the pre-fix auto-reschedule, the timer would re-arm itself
        // every 50 ms at the top of rejoinUntilConnected() and we'd see
        // the joinPush send count grow without bound. Count them after
        // several backoff intervals.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(
          pushSocket.joinPushCount,
          2,
          reason:
              'Expected exactly: 1 initial + 1 timeout-handler-scheduled '
              'retry. Observed ${pushSocket.joinPushCount} phx_join '
              'sends, which means rejoinUntilConnected is still '
              'auto-rescheduling on every tick regardless of whether '
              'a rejoin is in flight.',
        );
        ch.joinPush.trigger('ok', {});
      },
    );

    test(
      'still retries when the socket is disconnected',
      () async {
        // Socket reports disconnected; the timer should keep arming itself
        // so that once the socket comes back up the channel eventually
        // rejoins. Dart has no per-channel `socket.onOpen → rejoin` hook
        // like Phoenix does, so this fallback poll path is what keeps us
        // robust to socket downtime.
        final downSocket = _PushCountingSocket(
          'wss://example.com/socket',
          reconnectAfter: (_) => const Duration(milliseconds: 50),
        ).._isConnected = false;
        final ch = downSocket.channel('room:rejoin-while-down');

        // Kick off the first rejoin attempt ourselves; this is what
        // joinPush.receive('error') would do in production.
        // ignore: invalid_use_of_internal_member
        ch.rejoinUntilConnected();

        // No push should ever happen because the socket is disconnected.
        // But the timer should keep firing on each backoff tick: we
        // observe that indirectly by flipping to connected mid-way and
        // watching a rejoin fire from the next tick.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(
          downSocket.joinPushCount,
          0,
          reason: 'socket is down; no joinPush should have been sent',
        );

        downSocket._isConnected = true;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(
          downSocket.joinPushCount,
          greaterThanOrEqualTo(1),
          reason:
              'Once the socket reports connected, the next timer fire '
              'should drive rejoin() and send a phx_join. If this is 0 '
              'the reschedule-while-down fallback was removed.',
        );
        ch.joinPush.trigger('ok', {});
      },
    );
  });
}

/// Test-only socket that counts every outbound `phx_join` message and
/// lets the test toggle `isConnected` at will. Drops all pushes.
class _PushCountingSocket extends RealtimeClient {
  _PushCountingSocket(
    super.endpoint, {
    super.reconnectAfter,
  });

  int joinPushCount = 0;
  bool _isConnected = true;

  @override
  bool get isConnected => _isConnected;

  @override
  void push(Message message) {
    if (message.event == ChannelEvent.join) {
      joinPushCount++;
    }
  }
}
