// Regression tests for `RealtimeChannel.rejoin()` self-unsubscribe hazard.
//
// `RealtimeChannel.rejoin()` used to call `socket.leaveOpenTopic(topic)`
// which, when the channel itself was in `ChannelStates.joining` or
// `ChannelStates.joined`, would find the calling channel as its own
// "duplicate" and invoke `unsubscribe()` on it. That tore down the
// channel mid-rejoin: state transitioned to `leaving`, joinPush was
// destroyed, a leavePush was fired, and `ChannelEvents.close` was
// triggered — all while the caller's very next line was trying to set
// state back to `joining` and resend the joinPush.
//
// The hazard had been known to the author of `forceRejoin` — its
// doc-comment explicitly calls it out — but was only worked around for
// that one code path. The ordinary backoff-retry path still went
// through `rejoin()`, so any time rejoin was triggered while the
// channel was not already errored (e.g. a second rejoin-timer tick
// landing before the server's reply to the first), the
// self-unsubscribe fired.
//
// The fix extends `RealtimeClient.leaveOpenTopic` with an optional
// `except` parameter and has `rejoin()` pass `this`; siblings with the
// same topic are still evicted as before.
//
// Lives in its own file rather than `channel_test.dart` to avoid
// tail-of-file merge conflicts when this branch stacks with other
// fix/* branches off upstream/main — precedent: `b8085ff Revert
// union-merge attempt; move conflicting test to its own file instead`.

import 'dart:async';

import 'package:realtime_client/realtime_client.dart';
import 'package:realtime_client/src/message.dart';
import 'package:test/test.dart';

void main() {
  group('rejoin() self-unsubscribe', () {
    test(
      'calling rejoin() on a channel in joining state does not close it',
      () async {
        final socketStub = _DropPushSocket('wss://example.com/socket');
        final ch = socketStub.channel('room:self-unsubscribe');

        var closedFired = false;
        ch.subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.closed) {
            closedFired = true;
          }
        });

        // subscribe() called rejoin() which set state to joining. Sanity.
        expect(
          ch.isJoining,
          isTrue,
          reason: 'sanity: subscribe() puts the channel in joining state',
        );

        // Manually drive a second rejoin — this simulates what the rejoin
        // timer's auto-reschedule would do in production when the first
        // join hasn't been answered yet.
        // ignore: invalid_use_of_internal_member
        ch.rejoin();

        // Give any pending sync tasks a chance to dispatch.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          ch.isClosed,
          isFalse,
          reason:
              'Channel must not be closed by its own rejoin() call. If this '
              'is true, leaveOpenTopic found the calling channel as its '
              'own duplicate and invoked unsubscribe() on it.',
        );
        expect(
          closedFired,
          isFalse,
          reason:
              'The subscribe callback should not receive closed as a side '
              'effect of rejoin().',
        );
        expect(
          ch.isJoining,
          isTrue,
          reason:
              'After rejoin(), the channel should still be in joining '
              'state (awaiting the server reply), not leaving/closed.',
        );
        ch.joinPush.trigger('ok', {});
      },
    );

    test(
      'subscribing a new channel on the same topic still evicts the older one',
      () {
        // Regression guard: the `except` safeguard must not regress the
        // original intent of `leaveOpenTopic`. When a second channel is
        // subscribed to a topic that already has a live (joining or
        // joined) channel, the older one should still be unsubscribed —
        // `except: newer` only protects the caller, not siblings.
        final socketStub = _DropPushSocket('wss://example.com/socket');
        final older = socketStub.channel('room:dup-cleanup');
        older.subscribe(); // older is now in `joining`.
        expect(older.isJoining, isTrue);

        final newer = socketStub.channel('room:dup-cleanup');
        // newer.subscribe() calls rejoin() internally, which triggers
        // socket.leaveOpenTopic for the topic. older is the only channel
        // that matches (and is not newer), so it must be evicted.
        newer.subscribe();

        expect(
          older.isClosed || older.isLeaving,
          isTrue,
          reason:
              'leaveOpenTopic must still unsubscribe a sibling channel on '
              'the same topic when a new channel is subscribed.',
        );
      },
    );
  });
}

/// Test-only socket that pretends to be connected and drops outbound
/// messages on the floor. Sufficient to exercise the channel state
/// machine for the self-unsubscribe regression tests.
class _DropPushSocket extends RealtimeClient {
  _DropPushSocket(super.endpoint);

  @override
  bool get isConnected => true;

  @override
  String? push(Message message) => null;
}
