import 'dart:async';
import 'dart:collection';

import 'generated/model_hash.dart';
import 'generated/model_schema.dart';
import 'realtime_socket_kernel.dart';

typedef SocketEffectExecutor =
    FutureOr<void> Function(
      SocketModelEffect effect,
      SocketEffectContext context,
    );
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
  var _activeEffectBatches = 0;

  SocketModelState get state => _state;

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
        unawaited(_runEffects(request, result));
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _runEffects(
    _SocketRequest request,
    SocketTransitionResult result,
  ) async {
    _activeEffectBatches++;
    try {
      final context = SocketEffectContext(
        cause: request.cause,
        metadata: request.metadata,
      );
      for (final effect in result.effects) {
        await _executeEffect(effect, context);
      }
      request.completer.complete(result);
    } catch (error, stackTrace) {
      request.completer.completeError(error, stackTrace);
    } finally {
      _activeEffectBatches--;
      if (_activeEffectBatches == 0) {
        assert(
          _validateRepresentation?.call(_state) ?? true,
          'Socket shell resources do not match model obligations',
        );
      }
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
