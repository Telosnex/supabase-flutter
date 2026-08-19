import 'package:meta/meta.dart';

import 'generated/model_schema.dart';

/// A snapshot of the live shell resources the socket model is responsible for.
///
/// The shell owns real timers and sockets; the model owns obligations saying
/// which of them should exist. Snapshotting the shell lets that correspondence
/// be written as a pure predicate ([socketRepresentationMatches]), so the
/// predicate itself can be tested for false negatives (a leak it fails to
/// catch) and false positives (a legitimate state it rejects). Asserted
/// against a live client it can only ever show that the shell happens to
/// comply, never that the check is capable of detecting non-compliance.
@immutable
final class SocketShellSnapshot {
  const SocketShellSnapshot({
    required this.reconnectTimerLive,
    required this.reconnectTimerId,
    required this.heartbeatTimerLive,
    required this.heartbeatTimerId,
    required this.disconnectTimerLive,
    required this.disconnectTimerId,
    required this.pendingHeartbeatRef,
    required this.pendingHeartbeatGeneration,
    required this.transportGenerations,
    required this.terminalGenerationsReported,
  });

  /// Whether a reconnect timer is currently scheduled.
  final bool reconnectTimerLive;

  /// The model timer id the live reconnect timer was armed for, if any.
  final int? reconnectTimerId;

  final bool heartbeatTimerLive;
  final int? heartbeatTimerId;

  final bool disconnectTimerLive;
  final int? disconnectTimerId;

  /// The ref of the heartbeat the shell is still awaiting a reply for.
  final int? pendingHeartbeatRef;

  /// The generation that pending heartbeat was sent on.
  final int? pendingHeartbeatGeneration;

  /// Generations for which the shell currently holds a transport handle.
  final Set<int> transportGenerations;

  /// Generations already reported terminal, whose handles have been released.
  final Set<int> terminalGenerationsReported;
}

/// Whether [shell] holds exactly the resources [state] obliges it to hold.
///
/// Both directions are checked. The forward direction (obligation implies
/// resource) catches a timer that was never armed or a transport that was
/// never opened. The reverse direction (resource implies obligation) catches a
/// leak: a timer still ticking, or a socket still open, that the model no
/// longer owns and so will never cancel or close.
///
/// The reverse direction is the load-bearing one. A one-directional check only
/// restates the effect log, confirming that effects the model asked for were
/// performed, which is already true by construction. It cannot see a resource
/// the model never asked for and does not know about, which is precisely the
/// ownerless transport this package leaked in d9be969.
bool socketRepresentationMatches(
  SocketModelState state,
  SocketShellSnapshot shell,
) =>
    _timerMatches(
      armed: state.reconnectTimer.armed,
      obligationId: state.reconnectTimer.id,
      live: shell.reconnectTimerLive,
      liveId: shell.reconnectTimerId,
    ) &&
    _timerMatches(
      armed: state.heartbeatTimer.armed,
      obligationId: state.heartbeatTimer.id,
      live: shell.heartbeatTimerLive,
      liveId: shell.heartbeatTimerId,
    ) &&
    _timerMatches(
      armed: state.disconnectTimer.armed,
      obligationId: state.disconnectTimer.id,
      live: shell.disconnectTimerLive,
      liveId: shell.disconnectTimerId,
    ) &&
    _pendingHeartbeatMatches(state.pendingHeartbeat, shell) &&
    _transportsMatch(state, shell);

bool _timerMatches({
  required bool armed,
  required int obligationId,
  required bool live,
  required int? liveId,
}) => armed ? live && liveId == obligationId : !live && liveId == null;

bool _pendingHeartbeatMatches(HeartbeatDebt debt, SocketShellSnapshot shell) =>
    debt.active
    ? debt.ref == shell.pendingHeartbeatRef &&
          debt.generation == shell.pendingHeartbeatGeneration
    : shell.pendingHeartbeatRef == null &&
          shell.pendingHeartbeatGeneration == null;

bool _transportsMatch(SocketModelState state, SocketShellSnapshot shell) {
  // A handle for any generation other than the one the model owns is a socket
  // nothing will ever close.
  for (final generation in shell.transportGenerations) {
    if (generation != state.activeGeneration) return false;
  }
  if (state.activeGeneration == 0) return true;
  // The active generation may legitimately hold no handle once it has been
  // reported terminal and released, but before the model has processed that
  // termination.
  return shell.transportGenerations.contains(state.activeGeneration) ||
      shell.terminalGenerationsReported.contains(state.activeGeneration);
}
