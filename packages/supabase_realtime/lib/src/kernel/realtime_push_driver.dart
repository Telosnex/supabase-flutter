import 'dart:async';
import 'dart:collection';

import 'generated/model_hash.dart';
import 'generated/model_schema.dart';
import 'realtime_push_kernel.dart';
import 'realtime_socket_driver.dart' show SocketTraceSink;

/// Executes a single committed effect.
///
/// Executors must not block: effect batches are atomic with respect to the
/// event queue, which does not advance until the batch completes.
typedef PushEffectExecutor =
    void Function(PushModelEffect effect, Object? metadata);
typedef PushRepresentationValidator = bool Function(PushModelState state);

/// Serial event queue and sole state owner for one push exchange.
final class RealtimePushDriver {
  static var _nextInstance = 1;

  RealtimePushDriver({
    required PushEffectExecutor executeEffect,
    SocketTraceSink? traceSink,
    PushRepresentationValidator? validateRepresentation,
    String? instance,
    RealtimePushKernel kernel = const RealtimePushKernel(),
  }) : _executeEffect = executeEffect,
       _traceSink = traceSink,
       _validateRepresentation = validateRepresentation,
       _kernel = kernel,
       _instance = instance ?? 'push:${_nextInstance++}';

  final PushEffectExecutor _executeEffect;
  final SocketTraceSink? _traceSink;
  final PushRepresentationValidator? _validateRepresentation;
  final RealtimePushKernel _kernel;
  final String _instance;
  final Queue<_PushRequest> _events = Queue();

  PushModelState _state = RealtimePushKernel.initialState;
  var _sequence = 0;
  var _draining = false;

  PushModelState get state => _state;
  bool get sent => _state.sent;

  Future<PushTransitionResult> dispatch(
    PushModelEvent event, {
    Object? metadata,
  }) {
    final request = _PushRequest(event: event, metadata: metadata);
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
              'Push shell supplied an invalid event: '
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
          'machine': 'push',
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
        'Push shell resources do not match model obligations',
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
  void _runEffects(_PushRequest request, PushTransitionResult result) {
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

final class _PushRequest {
  _PushRequest({required this.event, required this.metadata});

  final PushModelEvent event;
  final Object? metadata;
  final completer = Completer<PushTransitionResult>();
}
