// Negative tests for the socket representation invariant.
//
// The invariant is asserted on every drain of the live client, but that only
// shows the shell happens to comply. It says nothing about whether the check
// could detect non-compliance. A one-directional check passes every one of
// those runs while being blind to leaks, which is exactly how the ownerless
// transport in d9be969 went unnoticed.
//
// These tests mutate the shell away from the model's obligations and require
// the predicate to reject each mutation. They are the reason the assertion is
// evidence rather than decoration.

import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_kernel.dart';
import 'package:supabase_realtime/src/kernel/socket_representation.dart';
import 'package:test/test.dart';

void main() {
  // An open socket on generation 4, with a live heartbeat timer (id 7) and one
  // outstanding heartbeat (ref 3).
  final open = RealtimeSocketKernel.initialState.copyWith(
    intent: SocketIntent.up,
    phase: SocketPhase.open,
    activeGeneration: 4,
    started: true,
    heartbeatTimer: const GenerationTimerObligation(
      armed: true,
      id: 7,
      generation: 4,
    ),
    pendingHeartbeat: const HeartbeatDebt(active: true, generation: 4, ref: 3),
  );

  // Defaults describe the shell that `open` obliges. Each test overrides one
  // field, so every failure names exactly one divergence.
  SocketShellSnapshot shellOf({
    bool reconnectTimerLive = false,
    int? reconnectTimerId,
    bool heartbeatTimerLive = true,
    int? heartbeatTimerId = 7,
    bool disconnectTimerLive = false,
    int? disconnectTimerId,
    int? pendingHeartbeatRef = 3,
    int? pendingHeartbeatGeneration = 4,
    Set<int> transportGenerations = const {4},
    Set<int> terminalGenerationsReported = const {},
  }) => SocketShellSnapshot(
    reconnectTimerLive: reconnectTimerLive,
    reconnectTimerId: reconnectTimerId,
    heartbeatTimerLive: heartbeatTimerLive,
    heartbeatTimerId: heartbeatTimerId,
    disconnectTimerLive: disconnectTimerLive,
    disconnectTimerId: disconnectTimerId,
    pendingHeartbeatRef: pendingHeartbeatRef,
    pendingHeartbeatGeneration: pendingHeartbeatGeneration,
    transportGenerations: transportGenerations,
    terminalGenerationsReported: terminalGenerationsReported,
  );

  test('accepts a shell holding exactly its obligations', () {
    expect(socketRepresentationMatches(open, shellOf()), isTrue);
  });

  group('rejects leaked resources', () {
    test('a transport for a generation the model does not own', () {
      // The d9be969 defect: a superseded open left a socket with no owner.
      expect(
        socketRepresentationMatches(
          open,
          shellOf(transportGenerations: const {4, 5}),
        ),
        isFalse,
      );
    });

    test('a transport still held after the model released it', () {
      final settled = RealtimeSocketKernel.initialState.copyWith(
        intent: SocketIntent.down,
        started: true,
      );
      expect(
        socketRepresentationMatches(
          settled,
          shellOf(
            heartbeatTimerLive: false,
            heartbeatTimerId: null,
            pendingHeartbeatRef: null,
            pendingHeartbeatGeneration: null,
          ),
        ),
        isFalse,
        reason: 'activeGeneration is 0, so no transport may remain open',
      );
    });

    test('a reconnect timer the model never armed', () {
      expect(
        socketRepresentationMatches(
          open,
          shellOf(reconnectTimerLive: true, reconnectTimerId: 9),
        ),
        isFalse,
      );
    });

    test('a disconnect timer the model never armed', () {
      expect(
        socketRepresentationMatches(
          open,
          shellOf(disconnectTimerLive: true, disconnectTimerId: 9),
        ),
        isFalse,
      );
    });

    test('a heartbeat timer still ticking after the model disarmed it', () {
      final disarmed = open.copyWith(
        heartbeatTimer: const GenerationTimerObligation(
          armed: false,
          id: 0,
          generation: 0,
        ),
      );
      expect(
        socketRepresentationMatches(disarmed, shellOf()),
        isFalse,
      );
    });

    test('a pending heartbeat ref the model has already settled', () {
      final settled = open.copyWith(
        pendingHeartbeat: const HeartbeatDebt(
          active: false,
          generation: 0,
          ref: 0,
        ),
      );
      expect(socketRepresentationMatches(settled, shellOf()), isFalse);
    });
  });

  group('rejects missing resources', () {
    test('no transport for the generation the model owns', () {
      expect(
        socketRepresentationMatches(
          open,
          shellOf(transportGenerations: const {}),
        ),
        isFalse,
      );
    });

    test('a heartbeat timer that was never armed', () {
      expect(
        socketRepresentationMatches(
          open,
          shellOf(heartbeatTimerLive: false, heartbeatTimerId: null),
        ),
        isFalse,
      );
    });

    test('a heartbeat timer armed for a superseded id', () {
      expect(
        socketRepresentationMatches(open, shellOf(heartbeatTimerId: 6)),
        isFalse,
        reason: 'a stale id means the live timer belongs to an older arm',
      );
    });

    test('no pending heartbeat ref while the model awaits a reply', () {
      expect(
        socketRepresentationMatches(
          open,
          shellOf(pendingHeartbeatRef: null),
        ),
        isFalse,
      );
    });

    test('a pending heartbeat sent on a different generation', () {
      expect(
        socketRepresentationMatches(
          open,
          shellOf(pendingHeartbeatGeneration: 3),
        ),
        isFalse,
      );
    });
  });

  test('accepts an owned generation already reported terminal', () {
    // Legitimate transient: the handle was released when the transport
    // terminated, but the model has not yet processed that event.
    expect(
      socketRepresentationMatches(
        open,
        shellOf(
          transportGenerations: const {},
          terminalGenerationsReported: const {4},
        ),
      ),
      isTrue,
    );
  });
}
