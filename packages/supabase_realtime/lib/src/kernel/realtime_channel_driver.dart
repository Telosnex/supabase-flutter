import 'dart:async';
import 'dart:collection';

import 'generated/model_hash.dart';
import 'generated/model_schema.dart';
import 'realtime_channel_kernel.dart';
import 'realtime_socket_driver.dart' show SocketTraceSink;

/// Executes a single committed effect.
///
/// Executors must not block: effect batches are atomic with respect to the
/// event queue, which does not advance until the batch completes.
typedef ChannelEffectExecutor =
    void Function(ChannelModelEffect effect, Object? metadata);
typedef ChannelRepresentationValidator =
    bool Function(
      ChannelModelState state,
    );

/// Serial event queue and sole state owner for one channel lifecycle.
final class RealtimeChannelDriver {
  RealtimeChannelDriver({
    required int channelId,
    required ChannelEffectExecutor executeEffect,
    SocketTraceSink? traceSink,
    ChannelRepresentationValidator? validateRepresentation,
    String? instance,
    RealtimeChannelKernel kernel = const RealtimeChannelKernel(),
  }) : _executeEffect = executeEffect,
       _traceSink = traceSink,
       _validateRepresentation = validateRepresentation,
       _instance = instance ?? 'channel:$channelId',
       _kernel = kernel,
       _state = RealtimeChannelKernel.initialState(channelId: channelId);

  final ChannelEffectExecutor _executeEffect;
  final SocketTraceSink? _traceSink;
  final ChannelRepresentationValidator? _validateRepresentation;
  final RealtimeChannelKernel _kernel;
  final String _instance;
  final Queue<_ChannelRequest> _events = Queue();

  ChannelModelState _state;
  var _sequence = 0;
  var _draining = false;

  ChannelModelState get state => _state;
  int get activeJoinEpoch => _state.activeJoinEpoch;
  bool get socketAvailable => _state.socketAvailable;
  ChannelPhase get phase => _state.phase;

  Future<ChannelTransitionResult> dispatch(
    ChannelModelEvent event, {
    Object? metadata,
  }) {
    final request = _ChannelRequest(event: event, metadata: metadata);
    _events.add(request);
    _drainEvents();
    return request.completer.future;
  }

  void _drainEvents() {
    if (_draining) return;
    _draining = true;
    try {
      while (_events.isNotEmpty) {
        final request = _events.removeFirst();
        final preState = _state;
        final result = _kernel.step(preState, request.event);
        if (result.disposition == TransitionDisposition.rejected) {
          request.completer.completeError(
            StateError(
              'Channel shell supplied an invalid event: '
              '${request.event.toJson()} from ${preState.toJson()}',
            ),
          );
          continue;
        }
        _state = result.postState;
        _sequence++;
        _traceSink?.call({
          'schemaHash': realtimeFormalManifestSha256,
          'modelHash': realtimeSocketModelSha256,
          'machine': 'channel',
          'instance': _instance,
          'sequence': _sequence,
          'event': request.event.toJson(),
          'action': result.action.wireName,
          'disposition': result.disposition.wireName,
          'preState': preState.toJson(),
          'postState': result.postState.toJson(),
          'effects': result.effects.map((effect) => effect.toJson()).toList(),
        });
        _runEffects(request, result);
      }
      // Checked at quiescence rather than per batch. An effect may enqueue a
      // follow-up event, so mid-cascade states are legitimately transient;
      // only the settled state must match the model's obligations.
      assert(
        _validateRepresentation?.call(_state) ?? true,
        'Channel shell resources do not match model obligations',
      );
    } finally {
      _draining = false;
    }
  }

  /// Runs one committed effect batch to completion.
  ///
  /// Batches are synchronous and atomic with respect to the event queue: no
  /// event can be observed between a state commit and the last effect of the
  /// batch that commit produced.
  void _runEffects(_ChannelRequest request, ChannelTransitionResult result) {
    try {
      for (final effect in result.effects) {
        _executeEffect(effect, request.metadata);
      }
      request.completer.complete(result);
    } catch (error, stackTrace) {
      request.completer.completeError(error, stackTrace);
    }
  }
}

final class _ChannelRequest {
  _ChannelRequest({required this.event, required this.metadata});

  final ChannelModelEvent event;
  final Object? metadata;
  final completer = Completer<ChannelTransitionResult>();
}
