import 'package:meta/meta.dart';

import 'generated/model_schema.dart';

/// A snapshot of the live shell resources a push is responsible for.
@immutable
final class PushShellSnapshot {
  const PushShellSnapshot({
    required this.timeoutTimerLive,
    required this.timeoutTimerId,
    required this.replyBound,
    required this.ref,
  });

  /// Whether a timeout timer is currently scheduled.
  final bool timeoutTimerLive;

  /// The model timer id the live timeout timer was armed for, if any.
  final int? timeoutTimerId;

  /// Whether a reply handler is currently registered on the channel.
  final bool replyBound;

  /// The wire ref this push is bound to; empty when unbound.
  final String ref;
}

/// Whether [shell] holds exactly the resources [state] obliges it to hold.
///
/// Both clauses are biconditional because both describe owned resources. A
/// reply handler left registered after the push reaches a terminal phase is a
/// leak: nothing will ever unregister it, and it holds the channel's callback
/// table open for a reply that can no longer arrive.
bool pushRepresentationMatches(PushModelState state, PushShellSnapshot shell) {
  // Liveness is not required while armed: a fired one-shot is legitimately
  // waiting for the model to process its event. The disarmed branch is the
  // leak-detecting one.
  final timeoutMatches = state.timeoutTimer.armed
      ? shell.timeoutTimerId == state.timeoutTimer.id
      : !shell.timeoutTimerLive && shell.timeoutTimerId == null;
  final replyMatches = state.phase == PushPhase.pending
      ? shell.replyBound && shell.ref.isNotEmpty
      : !shell.replyBound;
  return timeoutMatches && replyMatches;
}
