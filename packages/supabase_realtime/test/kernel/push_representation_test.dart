// Negative tests for the push representation invariant. See
// socket_representation_test.dart for why these exist.

import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/push_representation.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_kernel.dart';
import 'package:test/test.dart';

void main() {
  // A push in flight: reply handler bound, timeout timer id 2 armed.
  final pending = RealtimePushKernel.initialState.copyWith(
    phase: PushPhase.pending,
    sent: true,
    activeRef: 1,
    timeoutTimer: const RefTimerObligation(armed: true, id: 2, ref: 1),
  );

  PushShellSnapshot shellOf({
    bool timeoutTimerLive = true,
    int? timeoutTimerId = 2,
    bool replyBound = true,
    String ref = '1',
  }) => PushShellSnapshot(
    timeoutTimerLive: timeoutTimerLive,
    timeoutTimerId: timeoutTimerId,
    replyBound: replyBound,
    ref: ref,
  );

  test('accepts a shell holding exactly its obligations', () {
    expect(pushRepresentationMatches(pending, shellOf()), isTrue);
  });

  test('accepts a fired one-shot awaiting the model', () {
    expect(
      pushRepresentationMatches(pending, shellOf(timeoutTimerLive: false)),
      isTrue,
    );
  });

  group('rejects leaked resources', () {
    test('a reply handler still bound after the push settled', () {
      // Nothing will ever unregister it, and it holds the channel's callback
      // table open for a reply that can no longer arrive.
      final settled = pending.copyWith(
        phase: PushPhase.terminal,
        timeoutTimer: const RefTimerObligation(armed: false, id: 0, ref: 0),
      );
      expect(
        pushRepresentationMatches(
          settled,
          shellOf(timeoutTimerLive: false, timeoutTimerId: null),
        ),
        isFalse,
      );
    });

    test('a timeout timer still scheduled after the model disarmed it', () {
      final settled = pending.copyWith(
        phase: PushPhase.terminal,
        timeoutTimer: const RefTimerObligation(armed: false, id: 0, ref: 0),
      );
      expect(
        pushRepresentationMatches(settled, shellOf(replyBound: false)),
        isFalse,
      );
    });

    test('a timeout timer id retained after the model disarmed it', () {
      final settled = pending.copyWith(
        phase: PushPhase.terminal,
        timeoutTimer: const RefTimerObligation(armed: false, id: 0, ref: 0),
      );
      expect(
        pushRepresentationMatches(
          settled,
          shellOf(timeoutTimerLive: false, replyBound: false),
        ),
        isFalse,
      );
    });
  });

  group('rejects missing resources', () {
    test('a timeout timer armed for a superseded id', () {
      expect(
        pushRepresentationMatches(pending, shellOf(timeoutTimerId: 1)),
        isFalse,
      );
    });

    test('no reply handler while the push is pending', () {
      expect(
        pushRepresentationMatches(pending, shellOf(replyBound: false)),
        isFalse,
      );
    });

    test('no wire ref while the push is pending', () {
      expect(pushRepresentationMatches(pending, shellOf(ref: '')), isFalse);
    });
  });

  test('accepts a settled push holding nothing', () {
    final settled = pending.copyWith(
      phase: PushPhase.terminal,
      timeoutTimer: const RefTimerObligation(armed: false, id: 0, ref: 0),
    );
    expect(
      pushRepresentationMatches(
        settled,
        shellOf(
          timeoutTimerLive: false,
          timeoutTimerId: null,
          replyBound: false,
          ref: '',
        ),
      ),
      isTrue,
    );
  });
}
