// Negative tests for the channel representation invariant. See
// socket_representation_test.dart for why these exist: asserting the invariant
// against a live client only shows the shell happens to comply, never that the
// check can detect non-compliance.

import 'package:supabase_realtime/src/kernel/channel_representation.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_channel_kernel.dart';
import 'package:test/test.dart';

void main() {
  // A channel waiting to rejoin, with rejoin timer id 5 armed for epoch 2.
  final rejoining = RealtimeChannelKernel.initialState(channelId: 1).copyWith(
    phase: ChannelPhase.errored,
    activeJoinEpoch: 2,
    rejoinTimer: const EpochTimerObligation(armed: true, id: 5, epoch: 2),
  );

  ChannelShellSnapshot shellOf({
    bool rejoinTimerLive = true,
    int? rejoinTimerId = 5,
    String joinRef = 'ref-1',
  }) => ChannelShellSnapshot(
    rejoinTimerLive: rejoinTimerLive,
    rejoinTimerId: rejoinTimerId,
    joinRef: joinRef,
  );

  test('accepts a shell holding exactly its obligations', () {
    expect(channelRepresentationMatches(rejoining, shellOf()), isTrue);
  });

  test('accepts a fired one-shot awaiting the model', () {
    // The timer has fired but ChannelRejoinTimerFired has not been processed
    // yet, so nothing is scheduled while the obligation is still armed.
    expect(
      channelRepresentationMatches(rejoining, shellOf(rejoinTimerLive: false)),
      isTrue,
    );
  });

  group('rejects leaked resources', () {
    test('a rejoin timer still scheduled after the model disarmed it', () {
      final disarmed = rejoining.copyWith(
        rejoinTimer: const EpochTimerObligation(armed: false, id: 0, epoch: 0),
      );
      expect(channelRepresentationMatches(disarmed, shellOf()), isFalse);
    });

    test('a rejoin timer id retained after the model disarmed it', () {
      final disarmed = rejoining.copyWith(
        rejoinTimer: const EpochTimerObligation(armed: false, id: 0, epoch: 0),
      );
      expect(
        channelRepresentationMatches(
          disarmed,
          shellOf(rejoinTimerLive: false),
        ),
        isFalse,
        reason: 'a retained id lets a later cancel match a dead timer',
      );
    });
  });

  group('rejects missing resources', () {
    test('a rejoin timer armed for a superseded id', () {
      expect(
        channelRepresentationMatches(rejoining, shellOf(rejoinTimerId: 4)),
        isFalse,
      );
    });

    test('no rejoin timer at all while the model records one armed', () {
      expect(
        channelRepresentationMatches(
          rejoining,
          shellOf(rejoinTimerLive: false, rejoinTimerId: null),
        ),
        isFalse,
      );
    });

    test('no join ref while the channel is joining', () {
      final joining = rejoining.copyWith(phase: ChannelPhase.joining);
      expect(
        channelRepresentationMatches(joining, shellOf(joinRef: '')),
        isFalse,
      );
    });
  });

  test('accepts a join ref retained past the joining phase', () {
    // Deliberately one-directional: the ref matches the join reply and the
    // later leave, so it legitimately outlives the joining phase.
    final joined = rejoining.copyWith(
      phase: ChannelPhase.joined,
      rejoinTimer: const EpochTimerObligation(armed: false, id: 0, epoch: 0),
    );
    expect(
      channelRepresentationMatches(
        joined,
        shellOf(rejoinTimerLive: false, rejoinTimerId: null),
      ),
      isTrue,
    );
  });
}
