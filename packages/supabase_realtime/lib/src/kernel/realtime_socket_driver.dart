import 'dart:async';
import 'dart:collection';

import 'generated/model_hash.dart';
import 'generated/model_schema.dart';
import 'realtime_socket_kernel.dart';

/// Executes a single committed effect.
///
/// Executors must not block: they may start asynchronous work, but they must
/// return without awaiting it and post the outcome back as a new event (see
/// [RealtimeSocketDriver.post]). Holding an effect open across an await would
/// stall the whole event queue, because the queue does not advance until the
/// current batch completes.
typedef SocketEffectExecutor =
    void Function(SocketModelEffect effect, SocketEffectContext context);
typedef SocketTraceSink = void Function(Map<String, Object?> trace);
typedef SocketRepresentationValidator = bool Function(SocketModelState state);

final class SocketEffectContext {
  const SocketEffectContext({this.cause, this.metadata});

  final Object? cause;
  final Object? metadata;
}

/// Serial event queue and sole state owner around the pure socket reducer.
final class RealtimeSocketDriver {
  RealtimeSocketDriver({
    required SocketEffectExecutor executeEffect,
    SocketTraceSink? traceSink,
    SocketRepresentationValidator? validateRepresentation,
    String instance = 'socket',
    RealtimeSocketKernel kernel = const RealtimeSocketKernel(),
  }) : _executeEffect = executeEffect,
       _traceSink = traceSink,
       _validateRepresentation = validateRepresentation,
       _instance = instance,
       _kernel = kernel;

  final SocketEffectExecutor _executeEffect;
  final SocketTraceSink? _traceSink;
  final SocketRepresentationValidator? _validateRepresentation;
  final RealtimeSocketKernel _kernel;
  final String _instance;
  final Queue<_SocketRequest> _events = Queue();

  SocketModelState _state = RealtimeSocketKernel.initialState;
  var _sequence = 0;
  var _draining = false;

  SocketModelState get state => _state;

  /// Posts an event without waiting for it to be processed.
  ///
  /// This is how effects report asynchronous outcomes. An effect must never
  /// await [dispatch] on its own follow-up event: the queue does not advance
  /// until the current batch completes, so awaiting would deadlock.
  ///
  /// Errors are intentionally not swallowed. A failed post means either a
  /// contract-invalid event or a throwing effect, both of which are defects
  /// that should surface rather than be silently dropped.
  void post(SocketModelEvent event, {Object? cause, Object? metadata}) {
    unawaited(dispatch(event, cause: cause, metadata: metadata));
  }

  Future<SocketTransitionResult> dispatch(
    SocketModelEvent event, {
    Object? cause,
    Object? metadata,
  }) {
    final request = _SocketRequest(
      event: event,
      cause: cause,
      metadata: metadata,
    );
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
              'Socket shell supplied a contract-invalid event: '
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
          'machine': 'socket',
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
      // Checked at quiescence rather than per batch. An effect may post a
      // follow-up event (a synchronous transport failure, say), so mid-cascade
      // states are legitimately transient; only the settled state is required
      // to match the model's obligations.
      assert(
        _validateRepresentation?.call(_state) ?? true,
        'Socket shell resources do not match model obligations',
      );
    } finally {
      _draining = false;
    }
  }

  /// Runs one committed effect batch to completion.
  ///
  /// Batches are synchronous and atomic with respect to the event queue: no
  /// event can be observed between the state commit and the last effect of the
  /// batch it produced. Effects that need to report an asynchronous outcome
  /// [post] a new event instead of awaiting one.
  void _runEffects(_SocketRequest request, SocketTransitionResult result) {
    final context = SocketEffectContext(
      cause: request.cause,
      metadata: request.metadata,
    );
    try {
      for (final effect in result.effects) {
        _executeEffect(effect, context);
      }
      request.completer.complete(result);
    } catch (error, stackTrace) {
      request.completer.completeError(error, stackTrace);
    }
  }
}

final class _SocketRequest {
  _SocketRequest({
    required this.event,
    required this.cause,
    required this.metadata,
  });

  final SocketModelEvent event;
  final Object? cause;
  final Object? metadata;
  final completer = Completer<SocketTransitionResult>();
}
