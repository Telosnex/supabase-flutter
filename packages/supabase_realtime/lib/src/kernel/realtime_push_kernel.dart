import 'generated/model_schema.dart';

/// Pure lifecycle reducer for one request/reply push exchange.
final class RealtimePushKernel {
  const RealtimePushKernel();

  static const initialState = PushModelState(
    phase: PushPhase.idle,
    sent: false,
    activeRef: 0,
    nextRef: 1,
    timeoutTimer: RefTimerObligation(armed: false, id: 0, ref: 0),
    nextTimerId: 1,
    terminalStatus: ReplyStatus.none,
    terminalDelivered: false,
  );

  static const _noTimer = RefTimerObligation(armed: false, id: 0, ref: 0);

  PushTransitionResult step(PushModelState state, PushModelEvent event) =>
      switch (event.kind) {
        PushModelEventKind.pushSendRequested => _send(state),
        PushModelEventKind.pushPrepareRequested => _prepare(state),
        PushModelEventKind.pushResendRequested => _resend(state),
        PushModelEventKind.pushReplyReceived => _reply(state, event),
        PushModelEventKind.pushTimeoutFired => _timeout(state, event),
        PushModelEventKind.pushDestroyRequested => _destroy(state),
      };

  PushTransitionResult _send(PushModelState state) {
    if (state.phase == PushPhase.pending) {
      if (state.sent) {
        return _ignore(state, PushModelAction.ignorePushAlreadyPending);
      }
      return _result(
        PushModelAction.sendPreparedPush,
        state.copyWith(sent: true),
        [PushModelEffect.sendPush(ref: state.activeRef)],
      );
    }
    if (state.phase == PushPhase.terminal) {
      return _reject(state);
    }
    return _start(state, PushModelAction.startPush, const [], send: true);
  }

  PushTransitionResult _prepare(PushModelState state) {
    if (state.phase == PushPhase.pending) {
      return _ignore(state, PushModelAction.ignorePushAlreadyPending);
    }
    if (state.phase == PushPhase.terminal) return _reject(state);
    return _start(state, PushModelAction.preparePush, const [], send: false);
  }

  PushTransitionResult _resend(PushModelState state) => _start(
    state,
    PushModelAction.resendPush,
    _cancelEffects(state),
    send: true,
  );

  PushTransitionResult _start(
    PushModelState state,
    PushModelAction action,
    List<PushModelEffect> prefix, {
    required bool send,
  }) {
    final ref = state.nextRef;
    final timerId = state.nextTimerId;
    return _result(
      action,
      state.copyWith(
        phase: PushPhase.pending,
        sent: send,
        activeRef: ref,
        nextRef: ref + 1,
        timeoutTimer: RefTimerObligation(
          armed: true,
          id: timerId,
          ref: ref,
        ),
        nextTimerId: timerId + 1,
        terminalStatus: ReplyStatus.none,
        terminalDelivered: false,
      ),
      [
        ...prefix,
        PushModelEffect.bindPushReply(ref: ref),
        PushModelEffect.armPushTimeoutTimer(timerId: timerId, ref: ref),
        if (send) PushModelEffect.sendPush(ref: ref),
      ],
    );
  }

  PushTransitionResult _reply(PushModelState state, PushModelEvent event) {
    if (event.ref == null || event.ref! <= 0 || !_isReply(event.replyStatus)) {
      return _reject(state);
    }
    if (state.phase != PushPhase.pending || event.ref != state.activeRef) {
      return _ignore(state, PushModelAction.ignoreStalePushReply);
    }
    return _terminal(
      state,
      PushModelAction.acceptPushReply,
      event.replyStatus!,
    );
  }

  PushTransitionResult _timeout(PushModelState state, PushModelEvent event) {
    if (event.timerId == null || event.timerId! <= 0) return _reject(state);
    if (!state.timeoutTimer.armed || event.timerId != state.timeoutTimer.id) {
      return _ignore(state, PushModelAction.ignoreStalePushTimer);
    }
    if (state.phase != PushPhase.pending ||
        state.timeoutTimer.ref != state.activeRef) {
      return _reject(state);
    }
    return _terminal(state, PushModelAction.timeoutPush, ReplyStatus.timeout);
  }

  PushTransitionResult _terminal(
    PushModelState state,
    PushModelAction action,
    ReplyStatus status,
  ) => _result(
    action,
    state.copyWith(
      phase: PushPhase.terminal,
      timeoutTimer: _noTimer,
      terminalStatus: status,
      terminalDelivered: true,
    ),
    [
      PushModelEffect.unbindPushReply(ref: state.activeRef),
      PushModelEffect.cancelPushTimeoutTimer(
        timerId: state.timeoutTimer.id,
      ),
      PushModelEffect.deliverPushResult(
        ref: state.activeRef,
        replyStatus: status,
      ),
    ],
  );

  PushTransitionResult _destroy(PushModelState state) => _result(
    PushModelAction.destroyPush,
    state.copyWith(
      phase: PushPhase.idle,
      sent: false,
      activeRef: 0,
      timeoutTimer: _noTimer,
      terminalStatus: ReplyStatus.none,
      terminalDelivered: false,
    ),
    _cancelEffects(state),
  );

  List<PushModelEffect> _cancelEffects(PushModelState state) =>
      state.phase == PushPhase.pending
      ? [
          PushModelEffect.unbindPushReply(ref: state.activeRef),
          PushModelEffect.cancelPushTimeoutTimer(
            timerId: state.timeoutTimer.id,
          ),
        ]
      : const [];

  bool _isReply(ReplyStatus? status) =>
      status == ReplyStatus.ok || status == ReplyStatus.error;

  PushTransitionResult _result(
    PushModelAction action,
    PushModelState state,
    List<PushModelEffect> effects,
  ) => PushTransitionResult(
    disposition: TransitionDisposition.applied,
    action: action,
    postState: state,
    effects: effects,
  );

  PushTransitionResult _ignore(
    PushModelState state,
    PushModelAction action,
  ) => PushTransitionResult(
    disposition: TransitionDisposition.ignored,
    action: action,
    postState: state,
    effects: const [],
  );

  PushTransitionResult _reject(PushModelState state) => PushTransitionResult(
    disposition: TransitionDisposition.rejected,
    action: PushModelAction.rejectPushContractViolation,
    postState: state,
    effects: const [],
  );
}
