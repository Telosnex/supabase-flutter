import 'generated/model_schema.dart';

/// Version-neutral event mapping used by the pinned v2.13 compatibility gate.
///
/// The production v2 package keeps its public callback API. Its adapter only
/// classifies callbacks into the same generated event vocabulary used by v3.
abstract final class RealtimeV213Adapter {
  static const implementationPin = '1444084fa5c09866c7d0781172ec00ff3d8d2075';

  static SocketModelEvent connect() => SocketModelEvent.connectRequested();
  static SocketModelEvent disconnect() =>
      SocketModelEvent.disconnectRequested();
  static SocketModelEvent transportOpened(int generation) =>
      SocketModelEvent.transportOpened(generation: generation);
  static SocketModelEvent transportOpenFailed(
    int generation, {
    required bool synchronous,
  }) => SocketModelEvent.transportOpenFailed(
    generation: generation,
    failureKind: synchronous ? FailureKind.syncValue : FailureKind.asyncValue,
  );
  static SocketModelEvent transportClosed(int generation) =>
      SocketModelEvent.transportClosed(
        generation: generation,
        failureKind: FailureKind.server,
      );
  static SocketModelEvent heartbeatTick(int timerId) =>
      SocketModelEvent.heartbeatTimerFired(timerId: timerId);
  static SocketModelEvent heartbeatReply(
    int generation,
    int ref, {
    required bool ok,
  }) => SocketModelEvent.heartbeatReplyReceived(
    generation: generation,
    ref: ref,
    heartbeatStatus: ok ? HeartbeatStatus.ok : HeartbeatStatus.error,
  );

  static ChannelModelEvent subscribe() =>
      ChannelModelEvent.channelSubscribeRequested();
  static ChannelModelEvent unsubscribe() =>
      ChannelModelEvent.channelUnsubscribeRequested();
  static ChannelModelEvent joinReply(
    int epoch,
    String status,
  ) => ChannelModelEvent.channelJoinReplyReceived(
    epoch: epoch,
    replyStatus: ReplyStatus.fromWire(status),
  );
  static ChannelModelEvent channelError(int epoch) =>
      ChannelModelEvent.channelErrorObserved(epoch: epoch);
  static ChannelModelEvent rejoinTimer(int timerId) =>
      ChannelModelEvent.channelRejoinTimerFired(timerId: timerId);

  static PushModelEvent sendPush() => PushModelEvent.pushSendRequested();
  static PushModelEvent resendPush() => PushModelEvent.pushResendRequested();
  static PushModelEvent pushReply(int ref, String status) =>
      PushModelEvent.pushReplyReceived(
        ref: ref,
        replyStatus: ReplyStatus.fromWire(status),
      );
  static PushModelEvent pushTimeout(int timerId) =>
      PushModelEvent.pushTimeoutFired(timerId: timerId);

  static String socketView(SocketModelState state) {
    if (!state.started) return 'closed';
    return switch (state.phase) {
      SocketPhase.connecting => 'connecting',
      SocketPhase.open => 'open',
      SocketPhase.closing when state.closeKind == CloseKind.user =>
        'disconnecting',
      SocketPhase.closing => 'open',
      SocketPhase.idle when state.intent == SocketIntent.up => 'closed',
      SocketPhase.idle => 'disconnected',
    };
  }
}
