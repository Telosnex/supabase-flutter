import 'generated/model_schema.dart';

/// Pure deterministic implementation of the socket lifecycle transition
/// relation in `formal/SocketTransitions.tla`.
final class RealtimeSocketKernel {
  /// Creates a kernel with a retry counter cap.
  ///
  /// Production uses the default effectively-unbounded cap. Finite
  /// conformance profiles pass the same cap as TLC's `MaxRetryCount`.
  const RealtimeSocketKernel({
    this.retryCountCap = 0x3fffffff,
  }) : assert(retryCountCap >= 0);

  final int retryCountCap;

  static const initialState = SocketModelState(
    intent: SocketIntent.down,
    phase: SocketPhase.idle,
    closeKind: CloseKind.none,
    afterClose: AfterClose.none,
    activeGeneration: 0,
    nextGeneration: 1,
    retryCount: 0,
    reconnectTimer: ReconnectTimerObligation(
      armed: false,
      id: 0,
      delayOrdinal: 0,
    ),
    heartbeatTimer: GenerationTimerObligation(
      armed: false,
      id: 0,
      generation: 0,
    ),
    disconnectTimer: TimerObligation(armed: false, id: 0),
    nextTimerId: 1,
    pendingHeartbeat: HeartbeatDebt(
      active: false,
      generation: 0,
      ref: 0,
    ),
    nextHeartbeatRef: 1,
    hasChannelDemand: false,
    started: false,
  );

  static const _noTimer = TimerObligation(armed: false, id: 0);
  static const _noReconnectTimer = ReconnectTimerObligation(
    armed: false,
    id: 0,
    delayOrdinal: 0,
  );
  static const _noGenerationTimer = GenerationTimerObligation(
    armed: false,
    id: 0,
    generation: 0,
  );
  static const _noHeartbeatDebt = HeartbeatDebt(
    active: false,
    generation: 0,
    ref: 0,
  );

  /// Applies one event without performing I/O or reading ambient state.
  SocketTransitionResult step(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (!_validEventPayload(event)) return _reject(state);
    return switch (event.kind) {
      SocketEventKind.connectRequested => _connectRequested(state),
      SocketEventKind.disconnectRequested => _disconnect(
        state,
        CloseReason.userDisconnect,
        SocketAction.beginUserClose,
      ),
      SocketEventKind.channelDemandAppeared => _channelDemandAppeared(state),
      SocketEventKind.channelDemandDisappeared => _channelDemandDisappeared(
        state,
        event,
      ),
      SocketEventKind.transportOpened => _transportOpened(state, event),
      SocketEventKind.transportOpenFailed => _transportOpenFailed(state, event),
      SocketEventKind.transportErrorObserved => _transportErrorObserved(
        state,
        event,
      ),
      SocketEventKind.transportClosed || SocketEventKind.transportCloseFailed =>
        _transportTerminated(state, event),
      SocketEventKind.heartbeatSendFailed => _heartbeatSendFailed(state, event),
      SocketEventKind.reconnectTimerFired => _reconnectTimerFired(state, event),
      SocketEventKind.heartbeatTimerFired => _heartbeatTimerFired(state, event),
      SocketEventKind.disconnectTimerFired => _disconnectTimerFired(
        state,
        event,
      ),
      SocketEventKind.heartbeatReplyReceived => _heartbeatReply(state, event),
    };
  }

  bool _validEventPayload(SocketModelEvent event) => switch (event.kind) {
    SocketEventKind.connectRequested ||
    SocketEventKind.disconnectRequested ||
    SocketEventKind.channelDemandAppeared => true,
    SocketEventKind.channelDemandDisappeared =>
      event.grace == GraceKind.zero || event.grace == GraceKind.nonzero,
    SocketEventKind.transportOpened => _positive(event.generation),
    SocketEventKind.transportOpenFailed =>
      _positive(event.generation) &&
          (event.failureKind == FailureKind.syncValue ||
              event.failureKind == FailureKind.asyncValue),
    SocketEventKind.transportErrorObserved =>
      _positive(event.generation) && event.failureKind == FailureKind.stream,
    SocketEventKind.transportClosed =>
      _positive(event.generation) &&
          (event.failureKind == FailureKind.server ||
              event.failureKind == FailureKind.requested ||
              event.failureKind == FailureKind.timeout),
    SocketEventKind.transportCloseFailed =>
      _positive(event.generation) &&
          (event.failureKind == FailureKind.asyncValue ||
              event.failureKind == FailureKind.timeout),
    SocketEventKind.heartbeatSendFailed =>
      _positive(event.generation) &&
          _positive(event.ref) &&
          (event.failureKind == FailureKind.syncValue ||
              event.failureKind == FailureKind.asyncValue ||
              event.failureKind == FailureKind.send),
    SocketEventKind.reconnectTimerFired ||
    SocketEventKind.heartbeatTimerFired ||
    SocketEventKind.disconnectTimerFired => _positive(event.timerId),
    SocketEventKind.heartbeatReplyReceived =>
      _positive(event.generation) &&
          _positive(event.ref) &&
          (event.heartbeatStatus == HeartbeatStatus.ok ||
              event.heartbeatStatus == HeartbeatStatus.error),
  };

  bool _positive(int? value) => value != null && value > 0;

  SocketTransitionResult _connectRequested(SocketModelState state) {
    final base = state.copyWith(
      intent: SocketIntent.up,
      started: true,
      retryCount: state.intent == SocketIntent.down ? 0 : state.retryCount,
      disconnectTimer: _noTimer,
    );
    final cancelDisconnect = _cancelDisconnectEffects(state);
    return switch (state.phase) {
      SocketPhase.idle => _result(
        SocketAction.startConnect,
        _startConnectState(state, base),
        [
          ...cancelDisconnect,
          ..._cancelReconnectEffects(state),
          SocketModelEffect.openTransport(
            generation: state.nextGeneration,
          ),
        ],
      ),
      SocketPhase.connecting || SocketPhase.open => _result(
        SocketAction.connectAlreadySatisfied,
        base,
        cancelDisconnect,
      ),
      SocketPhase.closing => _result(
        SocketAction.connectAfterCurrentClose,
        base.copyWith(afterClose: AfterClose.connectNow),
        cancelDisconnect,
      ),
    };
  }

  SocketModelState _startConnectState(
    SocketModelState allocationState,
    SocketModelState base,
  ) {
    final generation = allocationState.nextGeneration;
    return base.copyWith(
      phase: SocketPhase.connecting,
      closeKind: CloseKind.none,
      afterClose: AfterClose.none,
      activeGeneration: generation,
      nextGeneration: generation + 1,
      reconnectTimer: _noReconnectTimer,
      disconnectTimer: _noTimer,
      pendingHeartbeat: _noHeartbeatDebt,
    );
  }

  SocketModelState _downBase(SocketModelState state) => state.copyWith(
    intent: SocketIntent.down,
    retryCount: 0,
    reconnectTimer: _noReconnectTimer,
    heartbeatTimer: _noGenerationTimer,
    disconnectTimer: _noTimer,
    pendingHeartbeat: _noHeartbeatDebt,
  );

  SocketTransitionResult _disconnect(
    SocketModelState state,
    CloseReason reason,
    SocketAction action,
  ) {
    final base = _downBase(state);
    final cancelEffects = _cancelAllTimerEffects(state);
    return switch (state.phase) {
      SocketPhase.connecting || SocketPhase.open => _result(
        action,
        base.copyWith(
          phase: SocketPhase.closing,
          closeKind: CloseKind.user,
          afterClose: AfterClose.idle,
        ),
        [
          ...cancelEffects,
          SocketModelEffect.closeTransport(
            generation: state.activeGeneration,
            closeReason: reason,
          ),
        ],
      ),
      SocketPhase.closing => _result(
        action == SocketAction.fireDeferredDisconnect
            ? action
            : SocketAction.retargetCloseToIdle,
        base.copyWith(
          closeKind: CloseKind.user,
          afterClose: AfterClose.idle,
        ),
        cancelEffects,
      ),
      SocketPhase.idle => _result(
        action == SocketAction.fireDeferredDisconnect
            ? action
            : SocketAction.quiesceWithoutTransport,
        base.copyWith(
          closeKind: CloseKind.none,
          afterClose: AfterClose.none,
          activeGeneration: 0,
        ),
        cancelEffects,
      ),
    };
  }

  SocketTransitionResult _channelDemandAppeared(SocketModelState state) {
    if (state.hasChannelDemand) {
      return _result(
        SocketAction.channelDemandAlreadyRecorded,
        state,
        const [],
      );
    }
    final post = state.copyWith(
      hasChannelDemand: true,
      disconnectTimer: _noTimer,
    );
    if (state.disconnectTimer.armed) {
      return _result(
        SocketAction.cancelDeferredDisconnect,
        post,
        _cancelDisconnectEffects(state),
      );
    }
    return _result(SocketAction.recordChannelDemand, post, const []);
  }

  SocketTransitionResult _channelDemandDisappeared(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (!state.hasChannelDemand) {
      return _result(
        SocketAction.channelDemandAlreadyRecorded,
        state,
        const [],
      );
    }
    final withoutDemand = state.copyWith(hasChannelDemand: false);
    if (state.intent == SocketIntent.down) {
      return _result(
        SocketAction.recordEmptyDemandWithoutTimer,
        withoutDemand.copyWith(disconnectTimer: _noTimer),
        _cancelDisconnectEffects(state),
      );
    }
    if (event.grace == GraceKind.zero) {
      return _disconnect(
        withoutDemand,
        CloseReason.emptyChannels,
        SocketAction.disconnectEmptyDemandNow,
      );
    }
    if (event.grace == GraceKind.nonzero) {
      final timerId = state.nextTimerId;
      return _result(
        SocketAction.scheduleDeferredDisconnect,
        withoutDemand.copyWith(
          disconnectTimer: TimerObligation(armed: true, id: timerId),
          nextTimerId: timerId + 1,
        ),
        [
          ..._cancelDisconnectEffects(state),
          SocketModelEffect.armDisconnectTimer(timerId: timerId),
        ],
      );
    }
    return _reject(state);
  }

  SocketTransitionResult _transportOpened(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (event.generation != state.activeGeneration) {
      return _ignore(state, SocketAction.ignoreStaleTransportEvent);
    }
    if (state.phase != SocketPhase.connecting ||
        state.intent != SocketIntent.up) {
      return _ignore(state, SocketAction.ignoreSupersededOperationEvent);
    }
    final timerId = state.nextTimerId;
    return _result(
      SocketAction.acceptTransportOpen,
      state.copyWith(
        phase: SocketPhase.open,
        closeKind: CloseKind.none,
        afterClose: AfterClose.none,
        retryCount: 0,
        reconnectTimer: _noReconnectTimer,
        heartbeatTimer: GenerationTimerObligation(
          armed: true,
          id: timerId,
          generation: event.generation!,
        ),
        nextTimerId: timerId + 1,
        pendingHeartbeat: _noHeartbeatDebt,
      ),
      [
        ..._cancelReconnectEffects(state),
        SocketModelEffect.armHeartbeatTimer(
          timerId: timerId,
          generation: event.generation!,
        ),
        SocketModelEffect.emitConnectionOpen(),
      ],
    );
  }

  SocketTransitionResult _transportOpenFailed(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (event.generation != state.activeGeneration) {
      return _ignore(state, SocketAction.ignoreStaleTransportEvent);
    }
    if (state.phase != SocketPhase.connecting ||
        state.intent != SocketIntent.up) {
      return _ignore(state, SocketAction.ignoreSupersededOperationEvent);
    }
    final timerId = state.nextTimerId;
    final delay = _nextDelayOrdinal(state.retryCount);
    return _result(
      SocketAction.recoverOpenFailure,
      state.copyWith(
        phase: SocketPhase.idle,
        closeKind: CloseKind.none,
        afterClose: AfterClose.none,
        activeGeneration: 0,
        reconnectTimer: ReconnectTimerObligation(
          armed: true,
          id: timerId,
          delayOrdinal: delay,
        ),
        heartbeatTimer: _noGenerationTimer,
        nextTimerId: timerId + 1,
        pendingHeartbeat: _noHeartbeatDebt,
      ),
      [
        SocketModelEffect.emitConnectionError(
          failureKind: event.failureKind!,
        ),
        SocketModelEffect.notifyChannelsOfTransportError(
          failureKind: event.failureKind!,
        ),
        SocketModelEffect.armReconnectTimer(
          timerId: timerId,
          delayOrdinal: delay,
        ),
      ],
    );
  }

  SocketTransitionResult _transportErrorObserved(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (event.generation != state.activeGeneration) {
      return _ignore(state, SocketAction.ignoreStaleTransportEvent);
    }
    if (state.phase == SocketPhase.idle) return _reject(state);
    return _result(
      SocketAction.reportTransportError,
      state,
      [
        SocketModelEffect.emitConnectionError(
          failureKind: event.failureKind!,
        ),
        SocketModelEffect.notifyChannelsOfTransportError(
          failureKind: event.failureKind!,
        ),
      ],
    );
  }

  SocketModelState _closedBase(SocketModelState state) => state.copyWith(
    phase: SocketPhase.idle,
    closeKind: CloseKind.none,
    afterClose: AfterClose.none,
    activeGeneration: 0,
    heartbeatTimer: _noGenerationTimer,
    pendingHeartbeat: _noHeartbeatDebt,
  );

  List<SocketModelEffect> _closeOutcomeEffects(
    SocketModelState state,
    SocketModelEvent event,
  ) => [
    ..._cancelHeartbeatEffects(state),
    if (event.kind == SocketEventKind.transportCloseFailed)
      SocketModelEffect.emitConnectionError(
        failureKind: event.failureKind!,
      ),
    if (state.closeKind == CloseKind.recovery)
      SocketModelEffect.notifyChannelsOfTransportError(
        failureKind: event.failureKind!,
      ),
    SocketModelEffect.emitConnectionClosed(
      failureKind: event.failureKind!,
    ),
  ];

  SocketTransitionResult _finalizeCurrentClose(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    final plan = state.intent == SocketIntent.down
        ? AfterClose.idle
        : state.afterClose;
    final base = _closedBase(state);
    final commonEffects = _closeOutcomeEffects(state, event);
    return switch (plan) {
      AfterClose.connectNow => _result(
        SocketAction.settleCloseAndConnect,
        _startConnectState(state, base),
        [
          ...commonEffects,
          ..._cancelReconnectEffects(state),
          SocketModelEffect.openTransport(
            generation: state.nextGeneration,
          ),
        ],
      ),
      AfterClose.backoff => _armBackoffAfterClose(
        state,
        base,
        commonEffects,
      ),
      AfterClose.idle => _result(
        SocketAction.settleCloseIdle,
        base.copyWith(reconnectTimer: _noReconnectTimer),
        [...commonEffects, ..._cancelReconnectEffects(state)],
      ),
      AfterClose.none => _reject(state),
    };
  }

  SocketTransitionResult _armBackoffAfterClose(
    SocketModelState state,
    SocketModelState base,
    List<SocketModelEffect> commonEffects,
  ) {
    final timerId = state.nextTimerId;
    final delay = _nextDelayOrdinal(state.retryCount);
    return _result(
      SocketAction.settleCloseAndBackoff,
      base.copyWith(
        reconnectTimer: ReconnectTimerObligation(
          armed: true,
          id: timerId,
          delayOrdinal: delay,
        ),
        nextTimerId: timerId + 1,
      ),
      [
        ...commonEffects,
        SocketModelEffect.armReconnectTimer(
          timerId: timerId,
          delayOrdinal: delay,
        ),
      ],
    );
  }

  SocketTransitionResult _unexpectedClose(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    final base = _closedBase(state);
    final commonEffects = <SocketModelEffect>[
      ..._cancelHeartbeatEffects(state),
      SocketModelEffect.notifyChannelsOfTransportError(
        failureKind: event.failureKind!,
      ),
      SocketModelEffect.emitConnectionClosed(
        failureKind: event.failureKind!,
      ),
    ];
    if (state.intent == SocketIntent.up) {
      final timerId = state.nextTimerId;
      final delay = _nextDelayOrdinal(state.retryCount);
      return _result(
        SocketAction.recoverUnexpectedClose,
        base.copyWith(
          reconnectTimer: ReconnectTimerObligation(
            armed: true,
            id: timerId,
            delayOrdinal: delay,
          ),
          nextTimerId: timerId + 1,
        ),
        [
          ...commonEffects,
          SocketModelEffect.armReconnectTimer(
            timerId: timerId,
            delayOrdinal: delay,
          ),
        ],
      );
    }
    return _result(
      SocketAction.settleCloseIdle,
      base.copyWith(reconnectTimer: _noReconnectTimer),
      [...commonEffects, ..._cancelReconnectEffects(state)],
    );
  }

  SocketTransitionResult _transportTerminated(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (event.generation != state.activeGeneration) {
      return _ignore(state, SocketAction.ignoreStaleTransportEvent);
    }
    if (state.phase == SocketPhase.closing) {
      return _finalizeCurrentClose(state, event);
    }
    if (state.phase == SocketPhase.open &&
        event.kind == SocketEventKind.transportClosed) {
      return _unexpectedClose(state, event);
    }
    return _reject(state);
  }

  SocketTransitionResult _reconnectTimerFired(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (!state.reconnectTimer.armed ||
        event.timerId != state.reconnectTimer.id) {
      return _ignore(state, SocketAction.ignoreStaleTimerEvent);
    }
    if (state.intent != SocketIntent.up || state.phase != SocketPhase.idle) {
      return _reject(state);
    }
    final base = state.copyWith(
      retryCount: _consumeRetry(state.retryCount),
      reconnectTimer: _noReconnectTimer,
    );
    return _result(
      SocketAction.startReconnectAttempt,
      _startConnectState(state, base),
      [
        SocketModelEffect.openTransport(
          generation: state.nextGeneration,
        ),
      ],
    );
  }

  SocketTransitionResult _heartbeatTimerFired(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (!state.heartbeatTimer.armed ||
        event.timerId != state.heartbeatTimer.id) {
      return _ignore(state, SocketAction.ignoreStaleTimerEvent);
    }
    if (state.phase != SocketPhase.open ||
        state.heartbeatTimer.generation != state.activeGeneration) {
      return _reject(state);
    }
    if (!state.pendingHeartbeat.active) {
      final ref = state.nextHeartbeatRef;
      return _result(
        SocketAction.sendHeartbeat,
        state.copyWith(
          pendingHeartbeat: HeartbeatDebt(
            active: true,
            generation: state.activeGeneration,
            ref: ref,
          ),
          nextHeartbeatRef: ref + 1,
        ),
        [
          SocketModelEffect.sendHeartbeat(
            generation: state.activeGeneration,
            ref: ref,
          ),
          SocketModelEffect.emitHeartbeat(
            heartbeatStatus: HeartbeatStatus.sent,
          ),
          SocketModelEffect.resolveCurrentToken(
            tokenMode: TokenMode.currentSource,
          ),
        ],
      );
    }
    return _result(
      SocketAction.timeoutHeartbeat,
      state.copyWith(
        phase: SocketPhase.closing,
        closeKind: CloseKind.recovery,
        afterClose: AfterClose.backoff,
        heartbeatTimer: _noGenerationTimer,
        pendingHeartbeat: _noHeartbeatDebt,
      ),
      [
        ..._cancelHeartbeatEffects(state),
        SocketModelEffect.emitHeartbeat(
          heartbeatStatus: HeartbeatStatus.timeout,
        ),
        SocketModelEffect.closeTransport(
          generation: state.activeGeneration,
          closeReason: CloseReason.heartbeatTimeout,
        ),
      ],
    );
  }

  SocketTransitionResult _heartbeatReply(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (state.phase == SocketPhase.open &&
        state.pendingHeartbeat.active &&
        event.generation == state.activeGeneration &&
        event.generation == state.pendingHeartbeat.generation &&
        event.ref == state.pendingHeartbeat.ref) {
      return _result(
        SocketAction.acceptHeartbeatReply,
        state.copyWith(pendingHeartbeat: _noHeartbeatDebt),
        [
          SocketModelEffect.emitHeartbeat(
            heartbeatStatus: event.heartbeatStatus!,
          ),
        ],
      );
    }
    return _ignore(state, SocketAction.ignoreHeartbeatReply);
  }

  SocketTransitionResult _heartbeatSendFailed(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (event.generation != state.activeGeneration) {
      return _ignore(state, SocketAction.ignoreStaleTransportEvent);
    }
    if (state.phase == SocketPhase.open &&
        state.pendingHeartbeat.active &&
        event.generation == state.pendingHeartbeat.generation &&
        event.ref == state.pendingHeartbeat.ref) {
      return _result(
        SocketAction.recoverHeartbeatSendFailure,
        state.copyWith(
          phase: SocketPhase.closing,
          closeKind: CloseKind.recovery,
          afterClose: AfterClose.backoff,
          heartbeatTimer: _noGenerationTimer,
          pendingHeartbeat: _noHeartbeatDebt,
        ),
        [
          ..._cancelHeartbeatEffects(state),
          SocketModelEffect.emitHeartbeat(
            heartbeatStatus: HeartbeatStatus.error,
          ),
          SocketModelEffect.emitConnectionError(
            failureKind: event.failureKind!,
          ),
          SocketModelEffect.notifyChannelsOfTransportError(
            failureKind: event.failureKind!,
          ),
          SocketModelEffect.closeTransport(
            generation: state.activeGeneration,
            closeReason: CloseReason.transportFailure,
          ),
        ],
      );
    }
    return _ignore(state, SocketAction.ignoreHeartbeatReply);
  }

  SocketTransitionResult _disconnectTimerFired(
    SocketModelState state,
    SocketModelEvent event,
  ) {
    if (!state.disconnectTimer.armed ||
        event.timerId != state.disconnectTimer.id) {
      return _ignore(state, SocketAction.ignoreStaleTimerEvent);
    }
    if (state.hasChannelDemand) return _reject(state);
    return _disconnect(
      state,
      CloseReason.emptyChannels,
      SocketAction.fireDeferredDisconnect,
    );
  }

  int _nextDelayOrdinal(int retryCount) =>
      retryCount < retryCountCap ? retryCount + 1 : retryCountCap + 1;

  int _consumeRetry(int retryCount) =>
      retryCount < retryCountCap ? retryCount + 1 : retryCountCap;

  List<SocketModelEffect> _cancelReconnectEffects(SocketModelState state) =>
      state.reconnectTimer.armed
      ? [
          SocketModelEffect.cancelReconnectTimer(
            timerId: state.reconnectTimer.id,
          ),
        ]
      : const [];

  List<SocketModelEffect> _cancelHeartbeatEffects(SocketModelState state) =>
      state.heartbeatTimer.armed
      ? [
          SocketModelEffect.cancelHeartbeatTimer(
            timerId: state.heartbeatTimer.id,
          ),
        ]
      : const [];

  List<SocketModelEffect> _cancelDisconnectEffects(SocketModelState state) =>
      state.disconnectTimer.armed
      ? [
          SocketModelEffect.cancelDisconnectTimer(
            timerId: state.disconnectTimer.id,
          ),
        ]
      : const [];

  List<SocketModelEffect> _cancelAllTimerEffects(SocketModelState state) => [
    ..._cancelReconnectEffects(state),
    ..._cancelHeartbeatEffects(state),
    ..._cancelDisconnectEffects(state),
  ];

  SocketTransitionResult _result(
    SocketAction action,
    SocketModelState postState,
    List<SocketModelEffect> effects,
  ) => SocketTransitionResult(
    disposition: TransitionDisposition.applied,
    action: action,
    postState: postState,
    effects: effects,
  );

  SocketTransitionResult _ignore(
    SocketModelState state,
    SocketAction action,
  ) => SocketTransitionResult(
    disposition: TransitionDisposition.ignored,
    action: action,
    postState: state,
    effects: const [],
  );

  SocketTransitionResult _reject(SocketModelState state) =>
      SocketTransitionResult(
        disposition: TransitionDisposition.rejected,
        action: SocketAction.rejectContractViolation,
        postState: state,
        effects: const [],
      );
}
