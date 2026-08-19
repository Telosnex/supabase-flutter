import 'generated/model_schema.dart';

/// Pure lifecycle reducer for one Realtime channel.
final class RealtimeChannelKernel {
  const RealtimeChannelKernel();

  static ChannelModelState initialState({required int channelId}) =>
      ChannelModelState(
        channelId: channelId,
        intent: ChannelIntent.left,
        phase: ChannelPhase.closed,
        activeJoinEpoch: 0,
        nextJoinEpoch: 1,
        rejoinTimer: const EpochTimerObligation(
          armed: false,
          id: 0,
          epoch: 0,
        ),
        nextTimerId: 1,
        socketAvailable: false,
        started: false,
      );

  static const _noTimer = EpochTimerObligation(
    armed: false,
    id: 0,
    epoch: 0,
  );

  ChannelTransitionResult step(
    ChannelModelState state,
    ChannelModelEvent event,
  ) => switch (event.kind) {
    ChannelModelEventKind.channelSubscribeRequested => _subscribe(state),
    ChannelModelEventKind.channelManualRejoinRequested => _manualRejoin(
      state,
      evictDuplicates: true,
    ),
    ChannelModelEventKind.channelForceRejoinRequested => _manualRejoin(
      state,
      evictDuplicates: false,
    ),
    ChannelModelEventKind.channelWaitForSocketRequested => _waitForSocket(
      state,
    ),
    ChannelModelEventKind.channelUnsubscribeRequested => _unsubscribe(state),
    ChannelModelEventKind.channelSocketAvailabilityChanged =>
      _socketAvailability(state, event),
    ChannelModelEventKind.channelJoinReplyReceived => _joinReply(state, event),
    ChannelModelEventKind.channelErrorObserved => _error(state, event),
    ChannelModelEventKind.channelClosedObserved => _closed(state, event),
    ChannelModelEventKind.channelRejoinTimerFired => _rejoinTimerFired(
      state,
      event,
    ),
  };

  ChannelTransitionResult _waitForSocket(ChannelModelState state) {
    if (state.phase == ChannelPhase.leaving) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    if (state.socketAvailable) {
      return _manualRejoin(state, evictDuplicates: true);
    }
    final epoch = state.activeJoinEpoch > 0
        ? state.activeJoinEpoch
        : state.nextJoinEpoch;
    return _armRejoin(
      state.copyWith(
        intent: ChannelIntent.joined,
        phase: ChannelPhase.errored,
        activeJoinEpoch: epoch,
        nextJoinEpoch: state.activeJoinEpoch > 0
            ? state.nextJoinEpoch
            : epoch + 1,
        started: true,
      ),
      ChannelModelAction.waitForSocketToRejoin,
      ReplyStatus.error,
      emitError: false,
    );
  }

  ChannelTransitionResult _manualRejoin(
    ChannelModelState state, {
    required bool evictDuplicates,
  }) {
    if (state.phase == ChannelPhase.leaving) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    final base = state.copyWith(intent: ChannelIntent.joined, started: true);
    return _startJoin(
      base,
      ChannelModelAction.startChannelJoin,
      [
        ..._cancelTimerEffects(state),
        if (evictDuplicates)
          ChannelModelEffect.evictDuplicateChannels(
            requesterChannelId: state.channelId,
          ),
      ],
    );
  }

  ChannelTransitionResult _subscribe(ChannelModelState state) {
    if (state.intent == ChannelIntent.joined &&
        (state.phase == ChannelPhase.joining ||
            state.phase == ChannelPhase.joined)) {
      return _result(
        ChannelModelAction.subscribeAlreadyActive,
        state,
        const [],
      );
    }
    if (state.phase == ChannelPhase.leaving) return _reject(state);
    return _startJoin(
      state.copyWith(intent: ChannelIntent.joined, started: true),
      ChannelModelAction.startChannelJoin,
      [
        ..._cancelTimerEffects(state),
        ChannelModelEffect.evictDuplicateChannels(
          requesterChannelId: state.channelId,
        ),
      ],
    );
  }

  ChannelTransitionResult _unsubscribe(ChannelModelState state) {
    if (state.phase == ChannelPhase.closed ||
        state.intent == ChannelIntent.left) {
      return _result(
        ChannelModelAction.channelAlreadyClosed,
        state.copyWith(
          intent: ChannelIntent.left,
          phase: ChannelPhase.closed,
          activeJoinEpoch: 0,
          rejoinTimer: _noTimer,
        ),
        [
          ..._cancelTimerEffects(state),
          ChannelModelEffect.emitChannelClosed(),
        ],
      );
    }
    if (state.phase == ChannelPhase.leaving) {
      return _result(
        ChannelModelAction.channelAlreadyClosed,
        state,
        const [],
      );
    }
    return _result(
      ChannelModelAction.beginChannelLeave,
      state.copyWith(
        intent: ChannelIntent.left,
        phase: ChannelPhase.leaving,
        rejoinTimer: _noTimer,
      ),
      [
        ..._cancelTimerEffects(state),
        ChannelModelEffect.sendChannelLeave(epoch: state.activeJoinEpoch),
      ],
    );
  }

  ChannelTransitionResult _socketAvailability(
    ChannelModelState state,
    ChannelModelEvent event,
  ) {
    if (event.available == null) return _reject(state);
    return _result(
      ChannelModelAction.recordSocketAvailability,
      state.copyWith(socketAvailable: event.available),
      const [],
    );
  }

  ChannelTransitionResult _joinReply(
    ChannelModelState state,
    ChannelModelEvent event,
  ) {
    if (event.epoch == null ||
        event.epoch! <= 0 ||
        !_isJoinReply(event.replyStatus)) {
      return _reject(state);
    }
    if (event.epoch != state.activeJoinEpoch) {
      return _ignore(state, ChannelModelAction.ignoreStaleChannelEvent);
    }
    if (state.phase == ChannelPhase.leaving ||
        state.phase == ChannelPhase.closed) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    if (state.phase == ChannelPhase.errored) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    if (state.phase != ChannelPhase.joining) return _reject(state);
    if (event.replyStatus == ReplyStatus.ok) {
      return _result(
        ChannelModelAction.acceptJoinReply,
        state.copyWith(
          phase: ChannelPhase.joined,
          rejoinTimer: _noTimer,
        ),
        [
          ..._cancelTimerEffects(state),
          ChannelModelEffect.emitChannelSubscribed(),
        ],
      );
    }
    return _failAndSchedule(
      state,
      ChannelModelAction.rejectJoinAndSchedule,
      event.replyStatus!,
    );
  }

  ChannelTransitionResult _error(
    ChannelModelState state,
    ChannelModelEvent event,
  ) {
    if (event.epoch == null || event.epoch! <= 0) return _reject(state);
    if (event.epoch != state.activeJoinEpoch) {
      return _ignore(state, ChannelModelAction.ignoreStaleChannelEvent);
    }
    if (state.phase == ChannelPhase.leaving ||
        state.phase == ChannelPhase.closed) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    if (state.phase == ChannelPhase.errored) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    if (state.phase != ChannelPhase.joining &&
        state.phase != ChannelPhase.joined) {
      return _reject(state);
    }
    return _failAndSchedule(
      state,
      ChannelModelAction.recordChannelError,
      ReplyStatus.error,
    );
  }

  ChannelTransitionResult _closed(
    ChannelModelState state,
    ChannelModelEvent event,
  ) {
    if (event.epoch == null || event.epoch! <= 0) return _reject(state);
    if (event.epoch != state.activeJoinEpoch) {
      return _ignore(state, ChannelModelAction.ignoreStaleChannelEvent);
    }
    if (state.phase == ChannelPhase.closed) {
      return _ignore(state, ChannelModelAction.ignoreSupersededJoinEvent);
    }
    return _result(
      ChannelModelAction.closeChannel,
      state.copyWith(
        intent: ChannelIntent.left,
        phase: ChannelPhase.closed,
        activeJoinEpoch: 0,
        rejoinTimer: _noTimer,
      ),
      [
        ..._cancelTimerEffects(state),
        ChannelModelEffect.emitChannelClosed(),
      ],
    );
  }

  ChannelTransitionResult _rejoinTimerFired(
    ChannelModelState state,
    ChannelModelEvent event,
  ) {
    if (event.timerId == null || event.timerId! <= 0) return _reject(state);
    if (!state.rejoinTimer.armed || event.timerId != state.rejoinTimer.id) {
      return _ignore(state, ChannelModelAction.ignoreStaleChannelEvent);
    }
    if (state.intent != ChannelIntent.joined ||
        state.phase != ChannelPhase.errored ||
        state.rejoinTimer.epoch != state.activeJoinEpoch) {
      return _reject(state);
    }
    final disarmed = state.copyWith(rejoinTimer: _noTimer);
    if (state.socketAvailable) {
      return _startJoin(
        disarmed,
        ChannelModelAction.startChannelRejoin,
        [
          ChannelModelEffect.cancelChannelRejoinTimer(
            timerId: state.rejoinTimer.id,
          ),
          ChannelModelEffect.evictDuplicateChannels(
            requesterChannelId: state.channelId,
          ),
        ],
      );
    }
    return _armRejoin(
      disarmed,
      ChannelModelAction.waitForSocketToRejoin,
      ReplyStatus.error,
      emitError: false,
    );
  }

  ChannelTransitionResult _startJoin(
    ChannelModelState state,
    ChannelModelAction action,
    List<ChannelModelEffect> prefix,
  ) {
    final epoch = state.nextJoinEpoch;
    return _result(
      action,
      state.copyWith(
        phase: ChannelPhase.joining,
        activeJoinEpoch: epoch,
        nextJoinEpoch: epoch + 1,
        rejoinTimer: _noTimer,
      ),
      [
        ...prefix,
        ChannelModelEffect.sendChannelJoin(epoch: epoch),
      ],
    );
  }

  ChannelTransitionResult _failAndSchedule(
    ChannelModelState state,
    ChannelModelAction action,
    ReplyStatus status,
  ) => _armRejoin(
    state.copyWith(phase: ChannelPhase.errored),
    action,
    status,
    emitError: true,
  );

  ChannelTransitionResult _armRejoin(
    ChannelModelState state,
    ChannelModelAction action,
    ReplyStatus status, {
    required bool emitError,
  }) {
    final timerId = state.nextTimerId;
    return _result(
      action,
      state.copyWith(
        rejoinTimer: EpochTimerObligation(
          armed: true,
          id: timerId,
          epoch: state.activeJoinEpoch,
        ),
        nextTimerId: timerId + 1,
      ),
      [
        ..._cancelTimerEffects(state),
        if (emitError) ChannelModelEffect.emitChannelError(replyStatus: status),
        ChannelModelEffect.armChannelRejoinTimer(
          timerId: timerId,
          epoch: state.activeJoinEpoch,
        ),
      ],
    );
  }

  List<ChannelModelEffect> _cancelTimerEffects(ChannelModelState state) =>
      state.rejoinTimer.armed
      ? [
          ChannelModelEffect.cancelChannelRejoinTimer(
            timerId: state.rejoinTimer.id,
          ),
        ]
      : const [];

  bool _isJoinReply(ReplyStatus? status) =>
      status == ReplyStatus.ok ||
      status == ReplyStatus.error ||
      status == ReplyStatus.timeout;

  ChannelTransitionResult _result(
    ChannelModelAction action,
    ChannelModelState state,
    List<ChannelModelEffect> effects,
  ) => ChannelTransitionResult(
    disposition: TransitionDisposition.applied,
    action: action,
    postState: state,
    effects: effects,
  );

  ChannelTransitionResult _ignore(
    ChannelModelState state,
    ChannelModelAction action,
  ) => ChannelTransitionResult(
    disposition: TransitionDisposition.ignored,
    action: action,
    postState: state,
    effects: const [],
  );

  ChannelTransitionResult _reject(ChannelModelState state) =>
      ChannelTransitionResult(
        disposition: TransitionDisposition.rejected,
        action: ChannelModelAction.rejectChannelContractViolation,
        postState: state,
        effects: const [],
      );
}
