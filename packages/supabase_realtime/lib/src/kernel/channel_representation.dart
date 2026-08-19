import 'package:meta/meta.dart';

import 'generated/model_schema.dart';

/// A snapshot of the live shell resources a channel is responsible for.
@immutable
final class ChannelShellSnapshot {
  const ChannelShellSnapshot({
    required this.rejoinTimerLive,
    required this.rejoinTimerId,
    required this.joinRef,
  });

  /// Whether a rejoin timer is currently scheduled.
  final bool rejoinTimerLive;

  /// The model timer id the live rejoin timer was armed for, if any.
  final int? rejoinTimerId;

  /// The join push's wire ref; empty until a join has been sent.
  final String joinRef;
}

/// Whether [shell] holds exactly the resources [state] obliges it to hold.
///
/// The rejoin timer is biconditional: it is an owned resource, so a timer
/// still scheduled after the model disarmed it is a leak that will fire a
/// rejoin nothing asked for.
///
/// The join ref is deliberately one-directional. It is an existence
/// requirement rather than an ownership obligation: the ref legitimately
/// outlives the joining phase, because it is what matches the join reply and
/// the later leave. Requiring it to be cleared would reject correct states.
bool channelRepresentationMatches(
  ChannelModelState state,
  ChannelShellSnapshot shell,
) {
  // Liveness is not required while armed: a fired one-shot is legitimately
  // waiting for the model to process its event. The disarmed branch is the
  // leak-detecting one.
  final rejoinMatches = state.rejoinTimer.armed
      ? shell.rejoinTimerId == state.rejoinTimer.id
      : !shell.rejoinTimerLive && shell.rejoinTimerId == null;
  final joinRefPresent =
      state.phase != ChannelPhase.joining || shell.joinRef.isNotEmpty;
  return rejoinMatches && joinRefPresent;
}
