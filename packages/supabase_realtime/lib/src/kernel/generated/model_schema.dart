// ignore_for_file: lines_longer_than_80_chars
// GENERATED FILE. DO NOT EDIT.
// Manifest SHA-256: d3c40e1dd47339350cb515eee28726c9ba4f55b563d69ece49a2b7dd5a66912b
// Schema version: 1

const realtimeFormalManifestSha256 =
    'd3c40e1dd47339350cb515eee28726c9ba4f55b563d69ece49a2b7dd5a66912b';
const realtimeFormalSchemaVersion = 1;

enum SocketIntent {
  up('up'),
  down('down');

  const SocketIntent(this.wireName);

  final String wireName;

  static SocketIntent fromWire(String value) => switch (value) {
    'up' => SocketIntent.up,
    'down' => SocketIntent.down,
    _ => throw FormatException('Unknown SocketIntent: $value'),
  };
}

enum SocketPhase {
  idle('idle'),
  connecting('connecting'),
  open('open'),
  closing('closing');

  const SocketPhase(this.wireName);

  final String wireName;

  static SocketPhase fromWire(String value) => switch (value) {
    'idle' => SocketPhase.idle,
    'connecting' => SocketPhase.connecting,
    'open' => SocketPhase.open,
    'closing' => SocketPhase.closing,
    _ => throw FormatException('Unknown SocketPhase: $value'),
  };
}

enum CloseKind {
  none('none'),
  user('user'),
  recovery('recovery');

  const CloseKind(this.wireName);

  final String wireName;

  static CloseKind fromWire(String value) => switch (value) {
    'none' => CloseKind.none,
    'user' => CloseKind.user,
    'recovery' => CloseKind.recovery,
    _ => throw FormatException('Unknown CloseKind: $value'),
  };
}

enum AfterClose {
  none('none'),
  idle('idle'),
  connectNow('connectNow'),
  backoff('backoff');

  const AfterClose(this.wireName);

  final String wireName;

  static AfterClose fromWire(String value) => switch (value) {
    'none' => AfterClose.none,
    'idle' => AfterClose.idle,
    'connectNow' => AfterClose.connectNow,
    'backoff' => AfterClose.backoff,
    _ => throw FormatException('Unknown AfterClose: $value'),
  };
}

enum FailureKind {
  none('none'),
  syncValue('sync'),
  asyncValue('async'),
  stream('stream'),
  server('server'),
  requested('requested'),
  timeout('timeout'),
  send('send');

  const FailureKind(this.wireName);

  final String wireName;

  static FailureKind fromWire(String value) => switch (value) {
    'none' => FailureKind.none,
    'sync' => FailureKind.syncValue,
    'async' => FailureKind.asyncValue,
    'stream' => FailureKind.stream,
    'server' => FailureKind.server,
    'requested' => FailureKind.requested,
    'timeout' => FailureKind.timeout,
    'send' => FailureKind.send,
    _ => throw FormatException('Unknown FailureKind: $value'),
  };
}

enum HeartbeatStatus {
  none('none'),
  sent('sent'),
  ok('ok'),
  error('error'),
  timeout('timeout');

  const HeartbeatStatus(this.wireName);

  final String wireName;

  static HeartbeatStatus fromWire(String value) => switch (value) {
    'none' => HeartbeatStatus.none,
    'sent' => HeartbeatStatus.sent,
    'ok' => HeartbeatStatus.ok,
    'error' => HeartbeatStatus.error,
    'timeout' => HeartbeatStatus.timeout,
    _ => throw FormatException('Unknown HeartbeatStatus: $value'),
  };
}

enum GraceKind {
  none('none'),
  zero('zero'),
  nonzero('nonzero');

  const GraceKind(this.wireName);

  final String wireName;

  static GraceKind fromWire(String value) => switch (value) {
    'none' => GraceKind.none,
    'zero' => GraceKind.zero,
    'nonzero' => GraceKind.nonzero,
    _ => throw FormatException('Unknown GraceKind: $value'),
  };
}

enum TransitionDisposition {
  applied('applied'),
  ignored('ignored'),
  rejected('rejected');

  const TransitionDisposition(this.wireName);

  final String wireName;

  static TransitionDisposition fromWire(String value) => switch (value) {
    'applied' => TransitionDisposition.applied,
    'ignored' => TransitionDisposition.ignored,
    'rejected' => TransitionDisposition.rejected,
    _ => throw FormatException('Unknown TransitionDisposition: $value'),
  };
}

enum TokenMode {
  none('none'),
  currentSource('currentSource'),
  cachedOverride('cachedOverride');

  const TokenMode(this.wireName);

  final String wireName;

  static TokenMode fromWire(String value) => switch (value) {
    'none' => TokenMode.none,
    'currentSource' => TokenMode.currentSource,
    'cachedOverride' => TokenMode.cachedOverride,
    _ => throw FormatException('Unknown TokenMode: $value'),
  };
}

enum CloseReason {
  none('none'),
  userDisconnect('userDisconnect'),
  emptyChannels('emptyChannels'),
  heartbeatTimeout('heartbeatTimeout'),
  transportFailure('transportFailure');

  const CloseReason(this.wireName);

  final String wireName;

  static CloseReason fromWire(String value) => switch (value) {
    'none' => CloseReason.none,
    'userDisconnect' => CloseReason.userDisconnect,
    'emptyChannels' => CloseReason.emptyChannels,
    'heartbeatTimeout' => CloseReason.heartbeatTimeout,
    'transportFailure' => CloseReason.transportFailure,
    _ => throw FormatException('Unknown CloseReason: $value'),
  };
}

enum ChannelIntent {
  joined('joined'),
  left('left');

  const ChannelIntent(this.wireName);

  final String wireName;

  static ChannelIntent fromWire(String value) => switch (value) {
    'joined' => ChannelIntent.joined,
    'left' => ChannelIntent.left,
    _ => throw FormatException('Unknown ChannelIntent: $value'),
  };
}

enum ChannelPhase {
  closed('closed'),
  joining('joining'),
  joined('joined'),
  errored('errored'),
  leaving('leaving');

  const ChannelPhase(this.wireName);

  final String wireName;

  static ChannelPhase fromWire(String value) => switch (value) {
    'closed' => ChannelPhase.closed,
    'joining' => ChannelPhase.joining,
    'joined' => ChannelPhase.joined,
    'errored' => ChannelPhase.errored,
    'leaving' => ChannelPhase.leaving,
    _ => throw FormatException('Unknown ChannelPhase: $value'),
  };
}

enum ReplyStatus {
  none('none'),
  ok('ok'),
  error('error'),
  timeout('timeout');

  const ReplyStatus(this.wireName);

  final String wireName;

  static ReplyStatus fromWire(String value) => switch (value) {
    'none' => ReplyStatus.none,
    'ok' => ReplyStatus.ok,
    'error' => ReplyStatus.error,
    'timeout' => ReplyStatus.timeout,
    _ => throw FormatException('Unknown ReplyStatus: $value'),
  };
}

enum PushPhase {
  idle('idle'),
  pending('pending'),
  terminal('terminal');

  const PushPhase(this.wireName);

  final String wireName;

  static PushPhase fromWire(String value) => switch (value) {
    'idle' => PushPhase.idle,
    'pending' => PushPhase.pending,
    'terminal' => PushPhase.terminal,
    _ => throw FormatException('Unknown PushPhase: $value'),
  };
}

enum SocketEventKind {
  connectRequested('ConnectRequested'),
  disconnectRequested('DisconnectRequested'),
  channelDemandAppeared('ChannelDemandAppeared'),
  channelDemandDisappeared('ChannelDemandDisappeared'),
  transportOpened('TransportOpened'),
  transportOpenFailed('TransportOpenFailed'),
  transportErrorObserved('TransportErrorObserved'),
  transportClosed('TransportClosed'),
  transportCloseFailed('TransportCloseFailed'),
  heartbeatSendFailed('HeartbeatSendFailed'),
  reconnectTimerFired('ReconnectTimerFired'),
  heartbeatTimerFired('HeartbeatTimerFired'),
  disconnectTimerFired('DisconnectTimerFired'),
  heartbeatReplyReceived('HeartbeatReplyReceived');

  const SocketEventKind(this.wireName);

  final String wireName;

  static SocketEventKind fromWire(String value) => switch (value) {
    'ConnectRequested' => SocketEventKind.connectRequested,
    'DisconnectRequested' => SocketEventKind.disconnectRequested,
    'ChannelDemandAppeared' => SocketEventKind.channelDemandAppeared,
    'ChannelDemandDisappeared' => SocketEventKind.channelDemandDisappeared,
    'TransportOpened' => SocketEventKind.transportOpened,
    'TransportOpenFailed' => SocketEventKind.transportOpenFailed,
    'TransportErrorObserved' => SocketEventKind.transportErrorObserved,
    'TransportClosed' => SocketEventKind.transportClosed,
    'TransportCloseFailed' => SocketEventKind.transportCloseFailed,
    'HeartbeatSendFailed' => SocketEventKind.heartbeatSendFailed,
    'ReconnectTimerFired' => SocketEventKind.reconnectTimerFired,
    'HeartbeatTimerFired' => SocketEventKind.heartbeatTimerFired,
    'DisconnectTimerFired' => SocketEventKind.disconnectTimerFired,
    'HeartbeatReplyReceived' => SocketEventKind.heartbeatReplyReceived,
    _ => throw FormatException('Unknown SocketEventKind: $value'),
  };
}

enum SocketAction {
  startConnect('startConnect'),
  connectAlreadySatisfied('connectAlreadySatisfied'),
  connectAfterCurrentClose('connectAfterCurrentClose'),
  beginUserClose('beginUserClose'),
  retargetCloseToIdle('retargetCloseToIdle'),
  quiesceWithoutTransport('quiesceWithoutTransport'),
  recordChannelDemand('recordChannelDemand'),
  recordEmptyDemandWithoutTimer('recordEmptyDemandWithoutTimer'),
  cancelDeferredDisconnect('cancelDeferredDisconnect'),
  scheduleDeferredDisconnect('scheduleDeferredDisconnect'),
  disconnectEmptyDemandNow('disconnectEmptyDemandNow'),
  channelDemandAlreadyRecorded('channelDemandAlreadyRecorded'),
  acceptTransportOpen('acceptTransportOpen'),
  recoverOpenFailure('recoverOpenFailure'),
  reportTransportError('reportTransportError'),
  settleCloseIdle('settleCloseIdle'),
  settleCloseAndConnect('settleCloseAndConnect'),
  settleCloseAndBackoff('settleCloseAndBackoff'),
  recoverUnexpectedClose('recoverUnexpectedClose'),
  startReconnectAttempt('startReconnectAttempt'),
  sendHeartbeat('sendHeartbeat'),
  timeoutHeartbeat('timeoutHeartbeat'),
  acceptHeartbeatReply('acceptHeartbeatReply'),
  recoverHeartbeatSendFailure('recoverHeartbeatSendFailure'),
  fireDeferredDisconnect('fireDeferredDisconnect'),
  ignoreStaleTransportEvent('ignoreStaleTransportEvent'),
  ignoreSupersededOperationEvent('ignoreSupersededOperationEvent'),
  ignoreStaleTimerEvent('ignoreStaleTimerEvent'),
  ignoreHeartbeatReply('ignoreHeartbeatReply'),
  rejectContractViolation('rejectContractViolation');

  const SocketAction(this.wireName);

  final String wireName;

  static SocketAction fromWire(String value) => switch (value) {
    'startConnect' => SocketAction.startConnect,
    'connectAlreadySatisfied' => SocketAction.connectAlreadySatisfied,
    'connectAfterCurrentClose' => SocketAction.connectAfterCurrentClose,
    'beginUserClose' => SocketAction.beginUserClose,
    'retargetCloseToIdle' => SocketAction.retargetCloseToIdle,
    'quiesceWithoutTransport' => SocketAction.quiesceWithoutTransport,
    'recordChannelDemand' => SocketAction.recordChannelDemand,
    'recordEmptyDemandWithoutTimer' =>
      SocketAction.recordEmptyDemandWithoutTimer,
    'cancelDeferredDisconnect' => SocketAction.cancelDeferredDisconnect,
    'scheduleDeferredDisconnect' => SocketAction.scheduleDeferredDisconnect,
    'disconnectEmptyDemandNow' => SocketAction.disconnectEmptyDemandNow,
    'channelDemandAlreadyRecorded' => SocketAction.channelDemandAlreadyRecorded,
    'acceptTransportOpen' => SocketAction.acceptTransportOpen,
    'recoverOpenFailure' => SocketAction.recoverOpenFailure,
    'reportTransportError' => SocketAction.reportTransportError,
    'settleCloseIdle' => SocketAction.settleCloseIdle,
    'settleCloseAndConnect' => SocketAction.settleCloseAndConnect,
    'settleCloseAndBackoff' => SocketAction.settleCloseAndBackoff,
    'recoverUnexpectedClose' => SocketAction.recoverUnexpectedClose,
    'startReconnectAttempt' => SocketAction.startReconnectAttempt,
    'sendHeartbeat' => SocketAction.sendHeartbeat,
    'timeoutHeartbeat' => SocketAction.timeoutHeartbeat,
    'acceptHeartbeatReply' => SocketAction.acceptHeartbeatReply,
    'recoverHeartbeatSendFailure' => SocketAction.recoverHeartbeatSendFailure,
    'fireDeferredDisconnect' => SocketAction.fireDeferredDisconnect,
    'ignoreStaleTransportEvent' => SocketAction.ignoreStaleTransportEvent,
    'ignoreSupersededOperationEvent' =>
      SocketAction.ignoreSupersededOperationEvent,
    'ignoreStaleTimerEvent' => SocketAction.ignoreStaleTimerEvent,
    'ignoreHeartbeatReply' => SocketAction.ignoreHeartbeatReply,
    'rejectContractViolation' => SocketAction.rejectContractViolation,
    _ => throw FormatException('Unknown SocketAction: $value'),
  };
}

enum SocketEffectKind {
  openTransport('OpenTransport'),
  closeTransport('CloseTransport'),
  armReconnectTimer('ArmReconnectTimer'),
  cancelReconnectTimer('CancelReconnectTimer'),
  armHeartbeatTimer('ArmHeartbeatTimer'),
  cancelHeartbeatTimer('CancelHeartbeatTimer'),
  armDisconnectTimer('ArmDisconnectTimer'),
  cancelDisconnectTimer('CancelDisconnectTimer'),
  sendHeartbeat('SendHeartbeat'),
  resolveCurrentToken('ResolveCurrentToken'),
  emitConnectionOpen('EmitConnectionOpen'),
  emitConnectionClosed('EmitConnectionClosed'),
  emitConnectionError('EmitConnectionError'),
  emitHeartbeat('EmitHeartbeat'),
  notifyChannelsOfTransportError('NotifyChannelsOfTransportError');

  const SocketEffectKind(this.wireName);

  final String wireName;

  static SocketEffectKind fromWire(String value) => switch (value) {
    'OpenTransport' => SocketEffectKind.openTransport,
    'CloseTransport' => SocketEffectKind.closeTransport,
    'ArmReconnectTimer' => SocketEffectKind.armReconnectTimer,
    'CancelReconnectTimer' => SocketEffectKind.cancelReconnectTimer,
    'ArmHeartbeatTimer' => SocketEffectKind.armHeartbeatTimer,
    'CancelHeartbeatTimer' => SocketEffectKind.cancelHeartbeatTimer,
    'ArmDisconnectTimer' => SocketEffectKind.armDisconnectTimer,
    'CancelDisconnectTimer' => SocketEffectKind.cancelDisconnectTimer,
    'SendHeartbeat' => SocketEffectKind.sendHeartbeat,
    'ResolveCurrentToken' => SocketEffectKind.resolveCurrentToken,
    'EmitConnectionOpen' => SocketEffectKind.emitConnectionOpen,
    'EmitConnectionClosed' => SocketEffectKind.emitConnectionClosed,
    'EmitConnectionError' => SocketEffectKind.emitConnectionError,
    'EmitHeartbeat' => SocketEffectKind.emitHeartbeat,
    'NotifyChannelsOfTransportError' =>
      SocketEffectKind.notifyChannelsOfTransportError,
    _ => throw FormatException('Unknown SocketEffectKind: $value'),
  };
}

enum ChannelModelEventKind {
  channelSubscribeRequested('ChannelSubscribeRequested'),
  channelManualRejoinRequested('ChannelManualRejoinRequested'),
  channelForceRejoinRequested('ChannelForceRejoinRequested'),
  channelWaitForSocketRequested('ChannelWaitForSocketRequested'),
  channelUnsubscribeRequested('ChannelUnsubscribeRequested'),
  channelSocketAvailabilityChanged('ChannelSocketAvailabilityChanged'),
  channelJoinReplyReceived('ChannelJoinReplyReceived'),
  channelErrorObserved('ChannelErrorObserved'),
  channelClosedObserved('ChannelClosedObserved'),
  channelRejoinTimerFired('ChannelRejoinTimerFired');

  const ChannelModelEventKind(this.wireName);

  final String wireName;

  static ChannelModelEventKind fromWire(String value) => switch (value) {
    'ChannelSubscribeRequested' =>
      ChannelModelEventKind.channelSubscribeRequested,
    'ChannelManualRejoinRequested' =>
      ChannelModelEventKind.channelManualRejoinRequested,
    'ChannelForceRejoinRequested' =>
      ChannelModelEventKind.channelForceRejoinRequested,
    'ChannelWaitForSocketRequested' =>
      ChannelModelEventKind.channelWaitForSocketRequested,
    'ChannelUnsubscribeRequested' =>
      ChannelModelEventKind.channelUnsubscribeRequested,
    'ChannelSocketAvailabilityChanged' =>
      ChannelModelEventKind.channelSocketAvailabilityChanged,
    'ChannelJoinReplyReceived' =>
      ChannelModelEventKind.channelJoinReplyReceived,
    'ChannelErrorObserved' => ChannelModelEventKind.channelErrorObserved,
    'ChannelClosedObserved' => ChannelModelEventKind.channelClosedObserved,
    'ChannelRejoinTimerFired' => ChannelModelEventKind.channelRejoinTimerFired,
    _ => throw FormatException('Unknown ChannelModelEventKind: $value'),
  };
}

enum ChannelModelAction {
  startChannelJoin('startChannelJoin'),
  subscribeAlreadyActive('subscribeAlreadyActive'),
  beginChannelLeave('beginChannelLeave'),
  channelAlreadyClosed('channelAlreadyClosed'),
  recordSocketAvailability('recordSocketAvailability'),
  acceptJoinReply('acceptJoinReply'),
  rejectJoinAndSchedule('rejectJoinAndSchedule'),
  recordChannelError('recordChannelError'),
  closeChannel('closeChannel'),
  startChannelRejoin('startChannelRejoin'),
  waitForSocketToRejoin('waitForSocketToRejoin'),
  ignoreStaleChannelEvent('ignoreStaleChannelEvent'),
  ignoreSupersededJoinEvent('ignoreSupersededJoinEvent'),
  rejectChannelContractViolation('rejectChannelContractViolation');

  const ChannelModelAction(this.wireName);

  final String wireName;

  static ChannelModelAction fromWire(String value) => switch (value) {
    'startChannelJoin' => ChannelModelAction.startChannelJoin,
    'subscribeAlreadyActive' => ChannelModelAction.subscribeAlreadyActive,
    'beginChannelLeave' => ChannelModelAction.beginChannelLeave,
    'channelAlreadyClosed' => ChannelModelAction.channelAlreadyClosed,
    'recordSocketAvailability' => ChannelModelAction.recordSocketAvailability,
    'acceptJoinReply' => ChannelModelAction.acceptJoinReply,
    'rejectJoinAndSchedule' => ChannelModelAction.rejectJoinAndSchedule,
    'recordChannelError' => ChannelModelAction.recordChannelError,
    'closeChannel' => ChannelModelAction.closeChannel,
    'startChannelRejoin' => ChannelModelAction.startChannelRejoin,
    'waitForSocketToRejoin' => ChannelModelAction.waitForSocketToRejoin,
    'ignoreStaleChannelEvent' => ChannelModelAction.ignoreStaleChannelEvent,
    'ignoreSupersededJoinEvent' => ChannelModelAction.ignoreSupersededJoinEvent,
    'rejectChannelContractViolation' =>
      ChannelModelAction.rejectChannelContractViolation,
    _ => throw FormatException('Unknown ChannelModelAction: $value'),
  };
}

enum ChannelModelEffectKind {
  sendChannelJoin('SendChannelJoin'),
  sendChannelLeave('SendChannelLeave'),
  armChannelRejoinTimer('ArmChannelRejoinTimer'),
  cancelChannelRejoinTimer('CancelChannelRejoinTimer'),
  evictDuplicateChannels('EvictDuplicateChannels'),
  emitChannelSubscribed('EmitChannelSubscribed'),
  emitChannelError('EmitChannelError'),
  emitChannelClosed('EmitChannelClosed');

  const ChannelModelEffectKind(this.wireName);

  final String wireName;

  static ChannelModelEffectKind fromWire(String value) => switch (value) {
    'SendChannelJoin' => ChannelModelEffectKind.sendChannelJoin,
    'SendChannelLeave' => ChannelModelEffectKind.sendChannelLeave,
    'ArmChannelRejoinTimer' => ChannelModelEffectKind.armChannelRejoinTimer,
    'CancelChannelRejoinTimer' =>
      ChannelModelEffectKind.cancelChannelRejoinTimer,
    'EvictDuplicateChannels' => ChannelModelEffectKind.evictDuplicateChannels,
    'EmitChannelSubscribed' => ChannelModelEffectKind.emitChannelSubscribed,
    'EmitChannelError' => ChannelModelEffectKind.emitChannelError,
    'EmitChannelClosed' => ChannelModelEffectKind.emitChannelClosed,
    _ => throw FormatException('Unknown ChannelModelEffectKind: $value'),
  };
}

enum PushModelEventKind {
  pushSendRequested('PushSendRequested'),
  pushPrepareRequested('PushPrepareRequested'),
  pushResendRequested('PushResendRequested'),
  pushReplyReceived('PushReplyReceived'),
  pushTimeoutFired('PushTimeoutFired'),
  pushDestroyRequested('PushDestroyRequested');

  const PushModelEventKind(this.wireName);

  final String wireName;

  static PushModelEventKind fromWire(String value) => switch (value) {
    'PushSendRequested' => PushModelEventKind.pushSendRequested,
    'PushPrepareRequested' => PushModelEventKind.pushPrepareRequested,
    'PushResendRequested' => PushModelEventKind.pushResendRequested,
    'PushReplyReceived' => PushModelEventKind.pushReplyReceived,
    'PushTimeoutFired' => PushModelEventKind.pushTimeoutFired,
    'PushDestroyRequested' => PushModelEventKind.pushDestroyRequested,
    _ => throw FormatException('Unknown PushModelEventKind: $value'),
  };
}

enum PushModelAction {
  startPush('startPush'),
  preparePush('preparePush'),
  sendPreparedPush('sendPreparedPush'),
  resendPush('resendPush'),
  acceptPushReply('acceptPushReply'),
  timeoutPush('timeoutPush'),
  destroyPush('destroyPush'),
  ignoreStalePushReply('ignoreStalePushReply'),
  ignoreStalePushTimer('ignoreStalePushTimer'),
  ignorePushAlreadyPending('ignorePushAlreadyPending'),
  rejectPushContractViolation('rejectPushContractViolation');

  const PushModelAction(this.wireName);

  final String wireName;

  static PushModelAction fromWire(String value) => switch (value) {
    'startPush' => PushModelAction.startPush,
    'preparePush' => PushModelAction.preparePush,
    'sendPreparedPush' => PushModelAction.sendPreparedPush,
    'resendPush' => PushModelAction.resendPush,
    'acceptPushReply' => PushModelAction.acceptPushReply,
    'timeoutPush' => PushModelAction.timeoutPush,
    'destroyPush' => PushModelAction.destroyPush,
    'ignoreStalePushReply' => PushModelAction.ignoreStalePushReply,
    'ignoreStalePushTimer' => PushModelAction.ignoreStalePushTimer,
    'ignorePushAlreadyPending' => PushModelAction.ignorePushAlreadyPending,
    'rejectPushContractViolation' =>
      PushModelAction.rejectPushContractViolation,
    _ => throw FormatException('Unknown PushModelAction: $value'),
  };
}

enum PushModelEffectKind {
  bindPushReply('BindPushReply'),
  unbindPushReply('UnbindPushReply'),
  armPushTimeoutTimer('ArmPushTimeoutTimer'),
  cancelPushTimeoutTimer('CancelPushTimeoutTimer'),
  sendPush('SendPush'),
  deliverPushResult('DeliverPushResult');

  const PushModelEffectKind(this.wireName);

  final String wireName;

  static PushModelEffectKind fromWire(String value) => switch (value) {
    'BindPushReply' => PushModelEffectKind.bindPushReply,
    'UnbindPushReply' => PushModelEffectKind.unbindPushReply,
    'ArmPushTimeoutTimer' => PushModelEffectKind.armPushTimeoutTimer,
    'CancelPushTimeoutTimer' => PushModelEffectKind.cancelPushTimeoutTimer,
    'SendPush' => PushModelEffectKind.sendPush,
    'DeliverPushResult' => PushModelEffectKind.deliverPushResult,
    _ => throw FormatException('Unknown PushModelEffectKind: $value'),
  };
}

final class TimerObligation {
  const TimerObligation({required this.armed, required this.id});

  final bool armed;
  final int id;

  factory TimerObligation.fromJson(Map<String, Object?> json) =>
      TimerObligation(
        armed: json['armed']! as bool,
        id: (json['id']! as num).toInt(),
      );

  Map<String, Object?> toJson() => {'armed': armed, 'id': id};

  TimerObligation copyWith({bool? armed, int? id}) =>
      TimerObligation(armed: armed ?? this.armed, id: id ?? this.id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerObligation && armed == other.armed && id == other.id;

  @override
  int get hashCode => Object.hashAll([armed, id]);

  @override
  String toString() => 'TimerObligation(${toJson()})';
}

final class ReconnectTimerObligation {
  const ReconnectTimerObligation({
    required this.armed,
    required this.id,
    required this.delayOrdinal,
  });

  final bool armed;
  final int id;
  final int delayOrdinal;

  factory ReconnectTimerObligation.fromJson(Map<String, Object?> json) =>
      ReconnectTimerObligation(
        armed: json['armed']! as bool,
        id: (json['id']! as num).toInt(),
        delayOrdinal: (json['delayOrdinal']! as num).toInt(),
      );

  Map<String, Object?> toJson() => {
    'armed': armed,
    'id': id,
    'delayOrdinal': delayOrdinal,
  };

  ReconnectTimerObligation copyWith({
    bool? armed,
    int? id,
    int? delayOrdinal,
  }) => ReconnectTimerObligation(
    armed: armed ?? this.armed,
    id: id ?? this.id,
    delayOrdinal: delayOrdinal ?? this.delayOrdinal,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReconnectTimerObligation &&
          armed == other.armed &&
          id == other.id &&
          delayOrdinal == other.delayOrdinal;

  @override
  int get hashCode => Object.hashAll([armed, id, delayOrdinal]);

  @override
  String toString() => 'ReconnectTimerObligation(${toJson()})';
}

final class GenerationTimerObligation {
  const GenerationTimerObligation({
    required this.armed,
    required this.id,
    required this.generation,
  });

  final bool armed;
  final int id;
  final int generation;

  factory GenerationTimerObligation.fromJson(Map<String, Object?> json) =>
      GenerationTimerObligation(
        armed: json['armed']! as bool,
        id: (json['id']! as num).toInt(),
        generation: (json['generation']! as num).toInt(),
      );

  Map<String, Object?> toJson() => {
    'armed': armed,
    'id': id,
    'generation': generation,
  };

  GenerationTimerObligation copyWith({bool? armed, int? id, int? generation}) =>
      GenerationTimerObligation(
        armed: armed ?? this.armed,
        id: id ?? this.id,
        generation: generation ?? this.generation,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationTimerObligation &&
          armed == other.armed &&
          id == other.id &&
          generation == other.generation;

  @override
  int get hashCode => Object.hashAll([armed, id, generation]);

  @override
  String toString() => 'GenerationTimerObligation(${toJson()})';
}

final class HeartbeatDebt {
  const HeartbeatDebt({
    required this.active,
    required this.generation,
    required this.ref,
  });

  final bool active;
  final int generation;
  final int ref;

  factory HeartbeatDebt.fromJson(Map<String, Object?> json) => HeartbeatDebt(
    active: json['active']! as bool,
    generation: (json['generation']! as num).toInt(),
    ref: (json['ref']! as num).toInt(),
  );

  Map<String, Object?> toJson() => {
    'active': active,
    'generation': generation,
    'ref': ref,
  };

  HeartbeatDebt copyWith({bool? active, int? generation, int? ref}) =>
      HeartbeatDebt(
        active: active ?? this.active,
        generation: generation ?? this.generation,
        ref: ref ?? this.ref,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeartbeatDebt &&
          active == other.active &&
          generation == other.generation &&
          ref == other.ref;

  @override
  int get hashCode => Object.hashAll([active, generation, ref]);

  @override
  String toString() => 'HeartbeatDebt(${toJson()})';
}

final class SocketModelState {
  const SocketModelState({
    required this.intent,
    required this.phase,
    required this.closeKind,
    required this.afterClose,
    required this.activeGeneration,
    required this.nextGeneration,
    required this.retryCount,
    required this.reconnectTimer,
    required this.heartbeatTimer,
    required this.disconnectTimer,
    required this.nextTimerId,
    required this.pendingHeartbeat,
    required this.nextHeartbeatRef,
    required this.hasChannelDemand,
    required this.started,
  });

  final SocketIntent intent;
  final SocketPhase phase;
  final CloseKind closeKind;
  final AfterClose afterClose;
  final int activeGeneration;
  final int nextGeneration;
  final int retryCount;
  final ReconnectTimerObligation reconnectTimer;
  final GenerationTimerObligation heartbeatTimer;
  final TimerObligation disconnectTimer;
  final int nextTimerId;
  final HeartbeatDebt pendingHeartbeat;
  final int nextHeartbeatRef;
  final bool hasChannelDemand;
  final bool started;

  factory SocketModelState.fromJson(Map<String, Object?> json) =>
      SocketModelState(
        intent: SocketIntent.fromWire(json['intent']! as String),
        phase: SocketPhase.fromWire(json['phase']! as String),
        closeKind: CloseKind.fromWire(json['closeKind']! as String),
        afterClose: AfterClose.fromWire(json['afterClose']! as String),
        activeGeneration: (json['activeGeneration']! as num).toInt(),
        nextGeneration: (json['nextGeneration']! as num).toInt(),
        retryCount: (json['retryCount']! as num).toInt(),
        reconnectTimer: ReconnectTimerObligation.fromJson(
          (json['reconnectTimer']! as Map).cast<String, Object?>(),
        ),
        heartbeatTimer: GenerationTimerObligation.fromJson(
          (json['heartbeatTimer']! as Map).cast<String, Object?>(),
        ),
        disconnectTimer: TimerObligation.fromJson(
          (json['disconnectTimer']! as Map).cast<String, Object?>(),
        ),
        nextTimerId: (json['nextTimerId']! as num).toInt(),
        pendingHeartbeat: HeartbeatDebt.fromJson(
          (json['pendingHeartbeat']! as Map).cast<String, Object?>(),
        ),
        nextHeartbeatRef: (json['nextHeartbeatRef']! as num).toInt(),
        hasChannelDemand: json['hasChannelDemand']! as bool,
        started: json['started']! as bool,
      );

  Map<String, Object?> toJson() => {
    'intent': intent.wireName,
    'phase': phase.wireName,
    'closeKind': closeKind.wireName,
    'afterClose': afterClose.wireName,
    'activeGeneration': activeGeneration,
    'nextGeneration': nextGeneration,
    'retryCount': retryCount,
    'reconnectTimer': reconnectTimer.toJson(),
    'heartbeatTimer': heartbeatTimer.toJson(),
    'disconnectTimer': disconnectTimer.toJson(),
    'nextTimerId': nextTimerId,
    'pendingHeartbeat': pendingHeartbeat.toJson(),
    'nextHeartbeatRef': nextHeartbeatRef,
    'hasChannelDemand': hasChannelDemand,
    'started': started,
  };

  SocketModelState copyWith({
    SocketIntent? intent,
    SocketPhase? phase,
    CloseKind? closeKind,
    AfterClose? afterClose,
    int? activeGeneration,
    int? nextGeneration,
    int? retryCount,
    ReconnectTimerObligation? reconnectTimer,
    GenerationTimerObligation? heartbeatTimer,
    TimerObligation? disconnectTimer,
    int? nextTimerId,
    HeartbeatDebt? pendingHeartbeat,
    int? nextHeartbeatRef,
    bool? hasChannelDemand,
    bool? started,
  }) => SocketModelState(
    intent: intent ?? this.intent,
    phase: phase ?? this.phase,
    closeKind: closeKind ?? this.closeKind,
    afterClose: afterClose ?? this.afterClose,
    activeGeneration: activeGeneration ?? this.activeGeneration,
    nextGeneration: nextGeneration ?? this.nextGeneration,
    retryCount: retryCount ?? this.retryCount,
    reconnectTimer: reconnectTimer ?? this.reconnectTimer,
    heartbeatTimer: heartbeatTimer ?? this.heartbeatTimer,
    disconnectTimer: disconnectTimer ?? this.disconnectTimer,
    nextTimerId: nextTimerId ?? this.nextTimerId,
    pendingHeartbeat: pendingHeartbeat ?? this.pendingHeartbeat,
    nextHeartbeatRef: nextHeartbeatRef ?? this.nextHeartbeatRef,
    hasChannelDemand: hasChannelDemand ?? this.hasChannelDemand,
    started: started ?? this.started,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocketModelState &&
          intent == other.intent &&
          phase == other.phase &&
          closeKind == other.closeKind &&
          afterClose == other.afterClose &&
          activeGeneration == other.activeGeneration &&
          nextGeneration == other.nextGeneration &&
          retryCount == other.retryCount &&
          reconnectTimer == other.reconnectTimer &&
          heartbeatTimer == other.heartbeatTimer &&
          disconnectTimer == other.disconnectTimer &&
          nextTimerId == other.nextTimerId &&
          pendingHeartbeat == other.pendingHeartbeat &&
          nextHeartbeatRef == other.nextHeartbeatRef &&
          hasChannelDemand == other.hasChannelDemand &&
          started == other.started;

  @override
  int get hashCode => Object.hashAll([
    intent,
    phase,
    closeKind,
    afterClose,
    activeGeneration,
    nextGeneration,
    retryCount,
    reconnectTimer,
    heartbeatTimer,
    disconnectTimer,
    nextTimerId,
    pendingHeartbeat,
    nextHeartbeatRef,
    hasChannelDemand,
    started,
  ]);

  @override
  String toString() => 'SocketModelState(${toJson()})';
}

final class EpochTimerObligation {
  const EpochTimerObligation({
    required this.armed,
    required this.id,
    required this.epoch,
  });

  final bool armed;
  final int id;
  final int epoch;

  factory EpochTimerObligation.fromJson(Map<String, Object?> json) =>
      EpochTimerObligation(
        armed: json['armed']! as bool,
        id: (json['id']! as num).toInt(),
        epoch: (json['epoch']! as num).toInt(),
      );

  Map<String, Object?> toJson() => {'armed': armed, 'id': id, 'epoch': epoch};

  EpochTimerObligation copyWith({bool? armed, int? id, int? epoch}) =>
      EpochTimerObligation(
        armed: armed ?? this.armed,
        id: id ?? this.id,
        epoch: epoch ?? this.epoch,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpochTimerObligation &&
          armed == other.armed &&
          id == other.id &&
          epoch == other.epoch;

  @override
  int get hashCode => Object.hashAll([armed, id, epoch]);

  @override
  String toString() => 'EpochTimerObligation(${toJson()})';
}

final class RefTimerObligation {
  const RefTimerObligation({
    required this.armed,
    required this.id,
    required this.ref,
  });

  final bool armed;
  final int id;
  final int ref;

  factory RefTimerObligation.fromJson(Map<String, Object?> json) =>
      RefTimerObligation(
        armed: json['armed']! as bool,
        id: (json['id']! as num).toInt(),
        ref: (json['ref']! as num).toInt(),
      );

  Map<String, Object?> toJson() => {'armed': armed, 'id': id, 'ref': ref};

  RefTimerObligation copyWith({bool? armed, int? id, int? ref}) =>
      RefTimerObligation(
        armed: armed ?? this.armed,
        id: id ?? this.id,
        ref: ref ?? this.ref,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefTimerObligation &&
          armed == other.armed &&
          id == other.id &&
          ref == other.ref;

  @override
  int get hashCode => Object.hashAll([armed, id, ref]);

  @override
  String toString() => 'RefTimerObligation(${toJson()})';
}

final class ChannelModelState {
  const ChannelModelState({
    required this.channelId,
    required this.intent,
    required this.phase,
    required this.activeJoinEpoch,
    required this.nextJoinEpoch,
    required this.rejoinTimer,
    required this.nextTimerId,
    required this.socketAvailable,
    required this.started,
  });

  final int channelId;
  final ChannelIntent intent;
  final ChannelPhase phase;
  final int activeJoinEpoch;
  final int nextJoinEpoch;
  final EpochTimerObligation rejoinTimer;
  final int nextTimerId;
  final bool socketAvailable;
  final bool started;

  factory ChannelModelState.fromJson(Map<String, Object?> json) =>
      ChannelModelState(
        channelId: (json['channelId']! as num).toInt(),
        intent: ChannelIntent.fromWire(json['intent']! as String),
        phase: ChannelPhase.fromWire(json['phase']! as String),
        activeJoinEpoch: (json['activeJoinEpoch']! as num).toInt(),
        nextJoinEpoch: (json['nextJoinEpoch']! as num).toInt(),
        rejoinTimer: EpochTimerObligation.fromJson(
          (json['rejoinTimer']! as Map).cast<String, Object?>(),
        ),
        nextTimerId: (json['nextTimerId']! as num).toInt(),
        socketAvailable: json['socketAvailable']! as bool,
        started: json['started']! as bool,
      );

  Map<String, Object?> toJson() => {
    'channelId': channelId,
    'intent': intent.wireName,
    'phase': phase.wireName,
    'activeJoinEpoch': activeJoinEpoch,
    'nextJoinEpoch': nextJoinEpoch,
    'rejoinTimer': rejoinTimer.toJson(),
    'nextTimerId': nextTimerId,
    'socketAvailable': socketAvailable,
    'started': started,
  };

  ChannelModelState copyWith({
    int? channelId,
    ChannelIntent? intent,
    ChannelPhase? phase,
    int? activeJoinEpoch,
    int? nextJoinEpoch,
    EpochTimerObligation? rejoinTimer,
    int? nextTimerId,
    bool? socketAvailable,
    bool? started,
  }) => ChannelModelState(
    channelId: channelId ?? this.channelId,
    intent: intent ?? this.intent,
    phase: phase ?? this.phase,
    activeJoinEpoch: activeJoinEpoch ?? this.activeJoinEpoch,
    nextJoinEpoch: nextJoinEpoch ?? this.nextJoinEpoch,
    rejoinTimer: rejoinTimer ?? this.rejoinTimer,
    nextTimerId: nextTimerId ?? this.nextTimerId,
    socketAvailable: socketAvailable ?? this.socketAvailable,
    started: started ?? this.started,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelModelState &&
          channelId == other.channelId &&
          intent == other.intent &&
          phase == other.phase &&
          activeJoinEpoch == other.activeJoinEpoch &&
          nextJoinEpoch == other.nextJoinEpoch &&
          rejoinTimer == other.rejoinTimer &&
          nextTimerId == other.nextTimerId &&
          socketAvailable == other.socketAvailable &&
          started == other.started;

  @override
  int get hashCode => Object.hashAll([
    channelId,
    intent,
    phase,
    activeJoinEpoch,
    nextJoinEpoch,
    rejoinTimer,
    nextTimerId,
    socketAvailable,
    started,
  ]);

  @override
  String toString() => 'ChannelModelState(${toJson()})';
}

final class PushModelState {
  const PushModelState({
    required this.phase,
    required this.sent,
    required this.activeRef,
    required this.nextRef,
    required this.timeoutTimer,
    required this.nextTimerId,
    required this.terminalStatus,
    required this.terminalDelivered,
  });

  final PushPhase phase;
  final bool sent;
  final int activeRef;
  final int nextRef;
  final RefTimerObligation timeoutTimer;
  final int nextTimerId;
  final ReplyStatus terminalStatus;
  final bool terminalDelivered;

  factory PushModelState.fromJson(Map<String, Object?> json) => PushModelState(
    phase: PushPhase.fromWire(json['phase']! as String),
    sent: json['sent']! as bool,
    activeRef: (json['activeRef']! as num).toInt(),
    nextRef: (json['nextRef']! as num).toInt(),
    timeoutTimer: RefTimerObligation.fromJson(
      (json['timeoutTimer']! as Map).cast<String, Object?>(),
    ),
    nextTimerId: (json['nextTimerId']! as num).toInt(),
    terminalStatus: ReplyStatus.fromWire(json['terminalStatus']! as String),
    terminalDelivered: json['terminalDelivered']! as bool,
  );

  Map<String, Object?> toJson() => {
    'phase': phase.wireName,
    'sent': sent,
    'activeRef': activeRef,
    'nextRef': nextRef,
    'timeoutTimer': timeoutTimer.toJson(),
    'nextTimerId': nextTimerId,
    'terminalStatus': terminalStatus.wireName,
    'terminalDelivered': terminalDelivered,
  };

  PushModelState copyWith({
    PushPhase? phase,
    bool? sent,
    int? activeRef,
    int? nextRef,
    RefTimerObligation? timeoutTimer,
    int? nextTimerId,
    ReplyStatus? terminalStatus,
    bool? terminalDelivered,
  }) => PushModelState(
    phase: phase ?? this.phase,
    sent: sent ?? this.sent,
    activeRef: activeRef ?? this.activeRef,
    nextRef: nextRef ?? this.nextRef,
    timeoutTimer: timeoutTimer ?? this.timeoutTimer,
    nextTimerId: nextTimerId ?? this.nextTimerId,
    terminalStatus: terminalStatus ?? this.terminalStatus,
    terminalDelivered: terminalDelivered ?? this.terminalDelivered,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushModelState &&
          phase == other.phase &&
          sent == other.sent &&
          activeRef == other.activeRef &&
          nextRef == other.nextRef &&
          timeoutTimer == other.timeoutTimer &&
          nextTimerId == other.nextTimerId &&
          terminalStatus == other.terminalStatus &&
          terminalDelivered == other.terminalDelivered;

  @override
  int get hashCode => Object.hashAll([
    phase,
    sent,
    activeRef,
    nextRef,
    timeoutTimer,
    nextTimerId,
    terminalStatus,
    terminalDelivered,
  ]);

  @override
  String toString() => 'PushModelState(${toJson()})';
}

final class SocketModelEvent {
  const SocketModelEvent._({
    required this.kind,
    this.grace,
    this.generation,
    this.failureKind,
    this.ref,
    this.timerId,
    this.heartbeatStatus,
  });

  factory SocketModelEvent.connectRequested() =>
      SocketModelEvent._(kind: SocketEventKind.connectRequested);

  factory SocketModelEvent.disconnectRequested() =>
      SocketModelEvent._(kind: SocketEventKind.disconnectRequested);

  factory SocketModelEvent.channelDemandAppeared() =>
      SocketModelEvent._(kind: SocketEventKind.channelDemandAppeared);

  factory SocketModelEvent.channelDemandDisappeared({
    required GraceKind grace,
  }) => SocketModelEvent._(
    kind: SocketEventKind.channelDemandDisappeared,
    grace: grace,
  );

  factory SocketModelEvent.transportOpened({required int generation}) =>
      SocketModelEvent._(
        kind: SocketEventKind.transportOpened,
        generation: generation,
      );

  factory SocketModelEvent.transportOpenFailed({
    required int generation,
    required FailureKind failureKind,
  }) => SocketModelEvent._(
    kind: SocketEventKind.transportOpenFailed,
    generation: generation,
    failureKind: failureKind,
  );

  factory SocketModelEvent.transportErrorObserved({
    required int generation,
    required FailureKind failureKind,
  }) => SocketModelEvent._(
    kind: SocketEventKind.transportErrorObserved,
    generation: generation,
    failureKind: failureKind,
  );

  factory SocketModelEvent.transportClosed({
    required int generation,
    required FailureKind failureKind,
  }) => SocketModelEvent._(
    kind: SocketEventKind.transportClosed,
    generation: generation,
    failureKind: failureKind,
  );

  factory SocketModelEvent.transportCloseFailed({
    required int generation,
    required FailureKind failureKind,
  }) => SocketModelEvent._(
    kind: SocketEventKind.transportCloseFailed,
    generation: generation,
    failureKind: failureKind,
  );

  factory SocketModelEvent.heartbeatSendFailed({
    required int generation,
    required int ref,
    required FailureKind failureKind,
  }) => SocketModelEvent._(
    kind: SocketEventKind.heartbeatSendFailed,
    generation: generation,
    ref: ref,
    failureKind: failureKind,
  );

  factory SocketModelEvent.reconnectTimerFired({required int timerId}) =>
      SocketModelEvent._(
        kind: SocketEventKind.reconnectTimerFired,
        timerId: timerId,
      );

  factory SocketModelEvent.heartbeatTimerFired({required int timerId}) =>
      SocketModelEvent._(
        kind: SocketEventKind.heartbeatTimerFired,
        timerId: timerId,
      );

  factory SocketModelEvent.disconnectTimerFired({required int timerId}) =>
      SocketModelEvent._(
        kind: SocketEventKind.disconnectTimerFired,
        timerId: timerId,
      );

  factory SocketModelEvent.heartbeatReplyReceived({
    required int generation,
    required int ref,
    required HeartbeatStatus heartbeatStatus,
  }) => SocketModelEvent._(
    kind: SocketEventKind.heartbeatReplyReceived,
    generation: generation,
    ref: ref,
    heartbeatStatus: heartbeatStatus,
  );

  final SocketEventKind kind;
  final GraceKind? grace;
  final int? generation;
  final FailureKind? failureKind;
  final int? ref;
  final int? timerId;
  final HeartbeatStatus? heartbeatStatus;

  factory SocketModelEvent.fromJson(Map<String, Object?> json) {
    final kind = SocketEventKind.fromWire(json['kind']! as String);
    return switch (kind) {
      SocketEventKind.connectRequested => SocketModelEvent.connectRequested(),
      SocketEventKind.disconnectRequested =>
        SocketModelEvent.disconnectRequested(),
      SocketEventKind.channelDemandAppeared =>
        SocketModelEvent.channelDemandAppeared(),
      SocketEventKind.channelDemandDisappeared =>
        SocketModelEvent.channelDemandDisappeared(
          grace: GraceKind.fromWire(json['grace']! as String),
        ),
      SocketEventKind.transportOpened => SocketModelEvent.transportOpened(
        generation: (json['generation']! as num).toInt(),
      ),
      SocketEventKind.transportOpenFailed =>
        SocketModelEvent.transportOpenFailed(
          generation: (json['generation']! as num).toInt(),
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
      SocketEventKind.transportErrorObserved =>
        SocketModelEvent.transportErrorObserved(
          generation: (json['generation']! as num).toInt(),
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
      SocketEventKind.transportClosed => SocketModelEvent.transportClosed(
        generation: (json['generation']! as num).toInt(),
        failureKind: FailureKind.fromWire(json['failureKind']! as String),
      ),
      SocketEventKind.transportCloseFailed =>
        SocketModelEvent.transportCloseFailed(
          generation: (json['generation']! as num).toInt(),
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
      SocketEventKind.heartbeatSendFailed =>
        SocketModelEvent.heartbeatSendFailed(
          generation: (json['generation']! as num).toInt(),
          ref: (json['ref']! as num).toInt(),
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
      SocketEventKind.reconnectTimerFired =>
        SocketModelEvent.reconnectTimerFired(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEventKind.heartbeatTimerFired =>
        SocketModelEvent.heartbeatTimerFired(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEventKind.disconnectTimerFired =>
        SocketModelEvent.disconnectTimerFired(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEventKind.heartbeatReplyReceived =>
        SocketModelEvent.heartbeatReplyReceived(
          generation: (json['generation']! as num).toInt(),
          ref: (json['ref']! as num).toInt(),
          heartbeatStatus: HeartbeatStatus.fromWire(
            json['heartbeatStatus']! as String,
          ),
        ),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    if (grace != null) 'grace': grace!.wireName,
    if (generation != null) 'generation': generation,
    if (failureKind != null) 'failureKind': failureKind!.wireName,
    if (ref != null) 'ref': ref,
    if (timerId != null) 'timerId': timerId,
    if (heartbeatStatus != null) 'heartbeatStatus': heartbeatStatus!.wireName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocketModelEvent &&
          kind == other.kind &&
          grace == other.grace &&
          generation == other.generation &&
          failureKind == other.failureKind &&
          ref == other.ref &&
          timerId == other.timerId &&
          heartbeatStatus == other.heartbeatStatus;

  @override
  int get hashCode => Object.hashAll([
    kind,
    grace,
    generation,
    failureKind,
    ref,
    timerId,
    heartbeatStatus,
  ]);

  @override
  String toString() => 'SocketModelEvent(${toJson()})';
}

final class SocketModelEffect {
  const SocketModelEffect._({
    required this.kind,
    this.generation,
    this.closeReason,
    this.timerId,
    this.delayOrdinal,
    this.ref,
    this.tokenMode,
    this.failureKind,
    this.heartbeatStatus,
  });

  factory SocketModelEffect.openTransport({required int generation}) =>
      SocketModelEffect._(
        kind: SocketEffectKind.openTransport,
        generation: generation,
      );

  factory SocketModelEffect.closeTransport({
    required int generation,
    required CloseReason closeReason,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.closeTransport,
    generation: generation,
    closeReason: closeReason,
  );

  factory SocketModelEffect.armReconnectTimer({
    required int timerId,
    required int delayOrdinal,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.armReconnectTimer,
    timerId: timerId,
    delayOrdinal: delayOrdinal,
  );

  factory SocketModelEffect.cancelReconnectTimer({required int timerId}) =>
      SocketModelEffect._(
        kind: SocketEffectKind.cancelReconnectTimer,
        timerId: timerId,
      );

  factory SocketModelEffect.armHeartbeatTimer({
    required int timerId,
    required int generation,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.armHeartbeatTimer,
    timerId: timerId,
    generation: generation,
  );

  factory SocketModelEffect.cancelHeartbeatTimer({required int timerId}) =>
      SocketModelEffect._(
        kind: SocketEffectKind.cancelHeartbeatTimer,
        timerId: timerId,
      );

  factory SocketModelEffect.armDisconnectTimer({required int timerId}) =>
      SocketModelEffect._(
        kind: SocketEffectKind.armDisconnectTimer,
        timerId: timerId,
      );

  factory SocketModelEffect.cancelDisconnectTimer({required int timerId}) =>
      SocketModelEffect._(
        kind: SocketEffectKind.cancelDisconnectTimer,
        timerId: timerId,
      );

  factory SocketModelEffect.sendHeartbeat({
    required int generation,
    required int ref,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.sendHeartbeat,
    generation: generation,
    ref: ref,
  );

  factory SocketModelEffect.resolveCurrentToken({
    required TokenMode tokenMode,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.resolveCurrentToken,
    tokenMode: tokenMode,
  );

  factory SocketModelEffect.emitConnectionOpen() =>
      SocketModelEffect._(kind: SocketEffectKind.emitConnectionOpen);

  factory SocketModelEffect.emitConnectionClosed({
    required FailureKind failureKind,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.emitConnectionClosed,
    failureKind: failureKind,
  );

  factory SocketModelEffect.emitConnectionError({
    required FailureKind failureKind,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.emitConnectionError,
    failureKind: failureKind,
  );

  factory SocketModelEffect.emitHeartbeat({
    required HeartbeatStatus heartbeatStatus,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.emitHeartbeat,
    heartbeatStatus: heartbeatStatus,
  );

  factory SocketModelEffect.notifyChannelsOfTransportError({
    required FailureKind failureKind,
  }) => SocketModelEffect._(
    kind: SocketEffectKind.notifyChannelsOfTransportError,
    failureKind: failureKind,
  );

  final SocketEffectKind kind;
  final int? generation;
  final CloseReason? closeReason;
  final int? timerId;
  final int? delayOrdinal;
  final int? ref;
  final TokenMode? tokenMode;
  final FailureKind? failureKind;
  final HeartbeatStatus? heartbeatStatus;

  factory SocketModelEffect.fromJson(Map<String, Object?> json) {
    final kind = SocketEffectKind.fromWire(json['kind']! as String);
    return switch (kind) {
      SocketEffectKind.openTransport => SocketModelEffect.openTransport(
        generation: (json['generation']! as num).toInt(),
      ),
      SocketEffectKind.closeTransport => SocketModelEffect.closeTransport(
        generation: (json['generation']! as num).toInt(),
        closeReason: CloseReason.fromWire(json['closeReason']! as String),
      ),
      SocketEffectKind.armReconnectTimer => SocketModelEffect.armReconnectTimer(
        timerId: (json['timerId']! as num).toInt(),
        delayOrdinal: (json['delayOrdinal']! as num).toInt(),
      ),
      SocketEffectKind.cancelReconnectTimer =>
        SocketModelEffect.cancelReconnectTimer(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEffectKind.armHeartbeatTimer => SocketModelEffect.armHeartbeatTimer(
        timerId: (json['timerId']! as num).toInt(),
        generation: (json['generation']! as num).toInt(),
      ),
      SocketEffectKind.cancelHeartbeatTimer =>
        SocketModelEffect.cancelHeartbeatTimer(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEffectKind.armDisconnectTimer =>
        SocketModelEffect.armDisconnectTimer(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEffectKind.cancelDisconnectTimer =>
        SocketModelEffect.cancelDisconnectTimer(
          timerId: (json['timerId']! as num).toInt(),
        ),
      SocketEffectKind.sendHeartbeat => SocketModelEffect.sendHeartbeat(
        generation: (json['generation']! as num).toInt(),
        ref: (json['ref']! as num).toInt(),
      ),
      SocketEffectKind.resolveCurrentToken =>
        SocketModelEffect.resolveCurrentToken(
          tokenMode: TokenMode.fromWire(json['tokenMode']! as String),
        ),
      SocketEffectKind.emitConnectionOpen =>
        SocketModelEffect.emitConnectionOpen(),
      SocketEffectKind.emitConnectionClosed =>
        SocketModelEffect.emitConnectionClosed(
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
      SocketEffectKind.emitConnectionError =>
        SocketModelEffect.emitConnectionError(
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
      SocketEffectKind.emitHeartbeat => SocketModelEffect.emitHeartbeat(
        heartbeatStatus: HeartbeatStatus.fromWire(
          json['heartbeatStatus']! as String,
        ),
      ),
      SocketEffectKind.notifyChannelsOfTransportError =>
        SocketModelEffect.notifyChannelsOfTransportError(
          failureKind: FailureKind.fromWire(json['failureKind']! as String),
        ),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    if (generation != null) 'generation': generation,
    if (closeReason != null) 'closeReason': closeReason!.wireName,
    if (timerId != null) 'timerId': timerId,
    if (delayOrdinal != null) 'delayOrdinal': delayOrdinal,
    if (ref != null) 'ref': ref,
    if (tokenMode != null) 'tokenMode': tokenMode!.wireName,
    if (failureKind != null) 'failureKind': failureKind!.wireName,
    if (heartbeatStatus != null) 'heartbeatStatus': heartbeatStatus!.wireName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocketModelEffect &&
          kind == other.kind &&
          generation == other.generation &&
          closeReason == other.closeReason &&
          timerId == other.timerId &&
          delayOrdinal == other.delayOrdinal &&
          ref == other.ref &&
          tokenMode == other.tokenMode &&
          failureKind == other.failureKind &&
          heartbeatStatus == other.heartbeatStatus;

  @override
  int get hashCode => Object.hashAll([
    kind,
    generation,
    closeReason,
    timerId,
    delayOrdinal,
    ref,
    tokenMode,
    failureKind,
    heartbeatStatus,
  ]);

  @override
  String toString() => 'SocketModelEffect(${toJson()})';
}

final class ChannelModelEvent {
  const ChannelModelEvent._({
    required this.kind,
    this.available,
    this.epoch,
    this.replyStatus,
    this.timerId,
  });

  factory ChannelModelEvent.channelSubscribeRequested() => ChannelModelEvent._(
    kind: ChannelModelEventKind.channelSubscribeRequested,
  );

  factory ChannelModelEvent.channelManualRejoinRequested() =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelManualRejoinRequested,
      );

  factory ChannelModelEvent.channelForceRejoinRequested() =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelForceRejoinRequested,
      );

  factory ChannelModelEvent.channelWaitForSocketRequested() =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelWaitForSocketRequested,
      );

  factory ChannelModelEvent.channelUnsubscribeRequested() =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelUnsubscribeRequested,
      );

  factory ChannelModelEvent.channelSocketAvailabilityChanged({
    required bool available,
  }) => ChannelModelEvent._(
    kind: ChannelModelEventKind.channelSocketAvailabilityChanged,
    available: available,
  );

  factory ChannelModelEvent.channelJoinReplyReceived({
    required int epoch,
    required ReplyStatus replyStatus,
  }) => ChannelModelEvent._(
    kind: ChannelModelEventKind.channelJoinReplyReceived,
    epoch: epoch,
    replyStatus: replyStatus,
  );

  factory ChannelModelEvent.channelErrorObserved({required int epoch}) =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelErrorObserved,
        epoch: epoch,
      );

  factory ChannelModelEvent.channelClosedObserved({required int epoch}) =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelClosedObserved,
        epoch: epoch,
      );

  factory ChannelModelEvent.channelRejoinTimerFired({required int timerId}) =>
      ChannelModelEvent._(
        kind: ChannelModelEventKind.channelRejoinTimerFired,
        timerId: timerId,
      );

  final ChannelModelEventKind kind;
  final bool? available;
  final int? epoch;
  final ReplyStatus? replyStatus;
  final int? timerId;

  factory ChannelModelEvent.fromJson(Map<String, Object?> json) {
    final kind = ChannelModelEventKind.fromWire(json['kind']! as String);
    return switch (kind) {
      ChannelModelEventKind.channelSubscribeRequested =>
        ChannelModelEvent.channelSubscribeRequested(),
      ChannelModelEventKind.channelManualRejoinRequested =>
        ChannelModelEvent.channelManualRejoinRequested(),
      ChannelModelEventKind.channelForceRejoinRequested =>
        ChannelModelEvent.channelForceRejoinRequested(),
      ChannelModelEventKind.channelWaitForSocketRequested =>
        ChannelModelEvent.channelWaitForSocketRequested(),
      ChannelModelEventKind.channelUnsubscribeRequested =>
        ChannelModelEvent.channelUnsubscribeRequested(),
      ChannelModelEventKind.channelSocketAvailabilityChanged =>
        ChannelModelEvent.channelSocketAvailabilityChanged(
          available: json['available']! as bool,
        ),
      ChannelModelEventKind.channelJoinReplyReceived =>
        ChannelModelEvent.channelJoinReplyReceived(
          epoch: (json['epoch']! as num).toInt(),
          replyStatus: ReplyStatus.fromWire(json['replyStatus']! as String),
        ),
      ChannelModelEventKind.channelErrorObserved =>
        ChannelModelEvent.channelErrorObserved(
          epoch: (json['epoch']! as num).toInt(),
        ),
      ChannelModelEventKind.channelClosedObserved =>
        ChannelModelEvent.channelClosedObserved(
          epoch: (json['epoch']! as num).toInt(),
        ),
      ChannelModelEventKind.channelRejoinTimerFired =>
        ChannelModelEvent.channelRejoinTimerFired(
          timerId: (json['timerId']! as num).toInt(),
        ),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    if (available != null) 'available': available,
    if (epoch != null) 'epoch': epoch,
    if (replyStatus != null) 'replyStatus': replyStatus!.wireName,
    if (timerId != null) 'timerId': timerId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelModelEvent &&
          kind == other.kind &&
          available == other.available &&
          epoch == other.epoch &&
          replyStatus == other.replyStatus &&
          timerId == other.timerId;

  @override
  int get hashCode =>
      Object.hashAll([kind, available, epoch, replyStatus, timerId]);

  @override
  String toString() => 'ChannelModelEvent(${toJson()})';
}

final class ChannelModelEffect {
  const ChannelModelEffect._({
    required this.kind,
    this.epoch,
    this.timerId,
    this.requesterChannelId,
    this.replyStatus,
  });

  factory ChannelModelEffect.sendChannelJoin({required int epoch}) =>
      ChannelModelEffect._(
        kind: ChannelModelEffectKind.sendChannelJoin,
        epoch: epoch,
      );

  factory ChannelModelEffect.sendChannelLeave({required int epoch}) =>
      ChannelModelEffect._(
        kind: ChannelModelEffectKind.sendChannelLeave,
        epoch: epoch,
      );

  factory ChannelModelEffect.armChannelRejoinTimer({
    required int timerId,
    required int epoch,
  }) => ChannelModelEffect._(
    kind: ChannelModelEffectKind.armChannelRejoinTimer,
    timerId: timerId,
    epoch: epoch,
  );

  factory ChannelModelEffect.cancelChannelRejoinTimer({required int timerId}) =>
      ChannelModelEffect._(
        kind: ChannelModelEffectKind.cancelChannelRejoinTimer,
        timerId: timerId,
      );

  factory ChannelModelEffect.evictDuplicateChannels({
    required int requesterChannelId,
  }) => ChannelModelEffect._(
    kind: ChannelModelEffectKind.evictDuplicateChannels,
    requesterChannelId: requesterChannelId,
  );

  factory ChannelModelEffect.emitChannelSubscribed() =>
      ChannelModelEffect._(kind: ChannelModelEffectKind.emitChannelSubscribed);

  factory ChannelModelEffect.emitChannelError({
    required ReplyStatus replyStatus,
  }) => ChannelModelEffect._(
    kind: ChannelModelEffectKind.emitChannelError,
    replyStatus: replyStatus,
  );

  factory ChannelModelEffect.emitChannelClosed() =>
      ChannelModelEffect._(kind: ChannelModelEffectKind.emitChannelClosed);

  final ChannelModelEffectKind kind;
  final int? epoch;
  final int? timerId;
  final int? requesterChannelId;
  final ReplyStatus? replyStatus;

  factory ChannelModelEffect.fromJson(Map<String, Object?> json) {
    final kind = ChannelModelEffectKind.fromWire(json['kind']! as String);
    return switch (kind) {
      ChannelModelEffectKind.sendChannelJoin =>
        ChannelModelEffect.sendChannelJoin(
          epoch: (json['epoch']! as num).toInt(),
        ),
      ChannelModelEffectKind.sendChannelLeave =>
        ChannelModelEffect.sendChannelLeave(
          epoch: (json['epoch']! as num).toInt(),
        ),
      ChannelModelEffectKind.armChannelRejoinTimer =>
        ChannelModelEffect.armChannelRejoinTimer(
          timerId: (json['timerId']! as num).toInt(),
          epoch: (json['epoch']! as num).toInt(),
        ),
      ChannelModelEffectKind.cancelChannelRejoinTimer =>
        ChannelModelEffect.cancelChannelRejoinTimer(
          timerId: (json['timerId']! as num).toInt(),
        ),
      ChannelModelEffectKind.evictDuplicateChannels =>
        ChannelModelEffect.evictDuplicateChannels(
          requesterChannelId: (json['requesterChannelId']! as num).toInt(),
        ),
      ChannelModelEffectKind.emitChannelSubscribed =>
        ChannelModelEffect.emitChannelSubscribed(),
      ChannelModelEffectKind.emitChannelError =>
        ChannelModelEffect.emitChannelError(
          replyStatus: ReplyStatus.fromWire(json['replyStatus']! as String),
        ),
      ChannelModelEffectKind.emitChannelClosed =>
        ChannelModelEffect.emitChannelClosed(),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    if (epoch != null) 'epoch': epoch,
    if (timerId != null) 'timerId': timerId,
    if (requesterChannelId != null) 'requesterChannelId': requesterChannelId,
    if (replyStatus != null) 'replyStatus': replyStatus!.wireName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelModelEffect &&
          kind == other.kind &&
          epoch == other.epoch &&
          timerId == other.timerId &&
          requesterChannelId == other.requesterChannelId &&
          replyStatus == other.replyStatus;

  @override
  int get hashCode =>
      Object.hashAll([kind, epoch, timerId, requesterChannelId, replyStatus]);

  @override
  String toString() => 'ChannelModelEffect(${toJson()})';
}

final class PushModelEvent {
  const PushModelEvent._({
    required this.kind,
    this.ref,
    this.replyStatus,
    this.timerId,
  });

  factory PushModelEvent.pushSendRequested() =>
      PushModelEvent._(kind: PushModelEventKind.pushSendRequested);

  factory PushModelEvent.pushPrepareRequested() =>
      PushModelEvent._(kind: PushModelEventKind.pushPrepareRequested);

  factory PushModelEvent.pushResendRequested() =>
      PushModelEvent._(kind: PushModelEventKind.pushResendRequested);

  factory PushModelEvent.pushReplyReceived({
    required int ref,
    required ReplyStatus replyStatus,
  }) => PushModelEvent._(
    kind: PushModelEventKind.pushReplyReceived,
    ref: ref,
    replyStatus: replyStatus,
  );

  factory PushModelEvent.pushTimeoutFired({required int timerId}) =>
      PushModelEvent._(
        kind: PushModelEventKind.pushTimeoutFired,
        timerId: timerId,
      );

  factory PushModelEvent.pushDestroyRequested() =>
      PushModelEvent._(kind: PushModelEventKind.pushDestroyRequested);

  final PushModelEventKind kind;
  final int? ref;
  final ReplyStatus? replyStatus;
  final int? timerId;

  factory PushModelEvent.fromJson(Map<String, Object?> json) {
    final kind = PushModelEventKind.fromWire(json['kind']! as String);
    return switch (kind) {
      PushModelEventKind.pushSendRequested =>
        PushModelEvent.pushSendRequested(),
      PushModelEventKind.pushPrepareRequested =>
        PushModelEvent.pushPrepareRequested(),
      PushModelEventKind.pushResendRequested =>
        PushModelEvent.pushResendRequested(),
      PushModelEventKind.pushReplyReceived => PushModelEvent.pushReplyReceived(
        ref: (json['ref']! as num).toInt(),
        replyStatus: ReplyStatus.fromWire(json['replyStatus']! as String),
      ),
      PushModelEventKind.pushTimeoutFired => PushModelEvent.pushTimeoutFired(
        timerId: (json['timerId']! as num).toInt(),
      ),
      PushModelEventKind.pushDestroyRequested =>
        PushModelEvent.pushDestroyRequested(),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    if (ref != null) 'ref': ref,
    if (replyStatus != null) 'replyStatus': replyStatus!.wireName,
    if (timerId != null) 'timerId': timerId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushModelEvent &&
          kind == other.kind &&
          ref == other.ref &&
          replyStatus == other.replyStatus &&
          timerId == other.timerId;

  @override
  int get hashCode => Object.hashAll([kind, ref, replyStatus, timerId]);

  @override
  String toString() => 'PushModelEvent(${toJson()})';
}

final class PushModelEffect {
  const PushModelEffect._({
    required this.kind,
    this.ref,
    this.timerId,
    this.replyStatus,
  });

  factory PushModelEffect.bindPushReply({required int ref}) =>
      PushModelEffect._(kind: PushModelEffectKind.bindPushReply, ref: ref);

  factory PushModelEffect.unbindPushReply({required int ref}) =>
      PushModelEffect._(kind: PushModelEffectKind.unbindPushReply, ref: ref);

  factory PushModelEffect.armPushTimeoutTimer({
    required int timerId,
    required int ref,
  }) => PushModelEffect._(
    kind: PushModelEffectKind.armPushTimeoutTimer,
    timerId: timerId,
    ref: ref,
  );

  factory PushModelEffect.cancelPushTimeoutTimer({required int timerId}) =>
      PushModelEffect._(
        kind: PushModelEffectKind.cancelPushTimeoutTimer,
        timerId: timerId,
      );

  factory PushModelEffect.sendPush({required int ref}) =>
      PushModelEffect._(kind: PushModelEffectKind.sendPush, ref: ref);

  factory PushModelEffect.deliverPushResult({
    required int ref,
    required ReplyStatus replyStatus,
  }) => PushModelEffect._(
    kind: PushModelEffectKind.deliverPushResult,
    ref: ref,
    replyStatus: replyStatus,
  );

  final PushModelEffectKind kind;
  final int? ref;
  final int? timerId;
  final ReplyStatus? replyStatus;

  factory PushModelEffect.fromJson(Map<String, Object?> json) {
    final kind = PushModelEffectKind.fromWire(json['kind']! as String);
    return switch (kind) {
      PushModelEffectKind.bindPushReply => PushModelEffect.bindPushReply(
        ref: (json['ref']! as num).toInt(),
      ),
      PushModelEffectKind.unbindPushReply => PushModelEffect.unbindPushReply(
        ref: (json['ref']! as num).toInt(),
      ),
      PushModelEffectKind.armPushTimeoutTimer =>
        PushModelEffect.armPushTimeoutTimer(
          timerId: (json['timerId']! as num).toInt(),
          ref: (json['ref']! as num).toInt(),
        ),
      PushModelEffectKind.cancelPushTimeoutTimer =>
        PushModelEffect.cancelPushTimeoutTimer(
          timerId: (json['timerId']! as num).toInt(),
        ),
      PushModelEffectKind.sendPush => PushModelEffect.sendPush(
        ref: (json['ref']! as num).toInt(),
      ),
      PushModelEffectKind.deliverPushResult =>
        PushModelEffect.deliverPushResult(
          ref: (json['ref']! as num).toInt(),
          replyStatus: ReplyStatus.fromWire(json['replyStatus']! as String),
        ),
    };
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    if (ref != null) 'ref': ref,
    if (timerId != null) 'timerId': timerId,
    if (replyStatus != null) 'replyStatus': replyStatus!.wireName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushModelEffect &&
          kind == other.kind &&
          ref == other.ref &&
          timerId == other.timerId &&
          replyStatus == other.replyStatus;

  @override
  int get hashCode => Object.hashAll([kind, ref, timerId, replyStatus]);

  @override
  String toString() => 'PushModelEffect(${toJson()})';
}

final class SocketTransitionResult {
  SocketTransitionResult({
    required this.disposition,
    required this.action,
    required this.postState,
    required List<SocketModelEffect> effects,
  }) : effects = List.unmodifiable(effects);

  final TransitionDisposition disposition;
  final SocketAction action;
  final SocketModelState postState;
  final List<SocketModelEffect> effects;

  Map<String, Object?> toJson() => {
    'disposition': disposition.wireName,
    'action': action.wireName,
    'postState': postState.toJson(),
    'effects': effects.map((effect) => effect.toJson()).toList(),
  };
}

final class ChannelTransitionResult {
  ChannelTransitionResult({
    required this.disposition,
    required this.action,
    required this.postState,
    required List<ChannelModelEffect> effects,
  }) : effects = List.unmodifiable(effects);

  final TransitionDisposition disposition;
  final ChannelModelAction action;
  final ChannelModelState postState;
  final List<ChannelModelEffect> effects;

  Map<String, Object?> toJson() => {
    'disposition': disposition.wireName,
    'action': action.wireName,
    'postState': postState.toJson(),
    'effects': effects.map((effect) => effect.toJson()).toList(),
  };
}

final class PushTransitionResult {
  PushTransitionResult({
    required this.disposition,
    required this.action,
    required this.postState,
    required List<PushModelEffect> effects,
  }) : effects = List.unmodifiable(effects);

  final TransitionDisposition disposition;
  final PushModelAction action;
  final PushModelState postState;
  final List<PushModelEffect> effects;

  Map<String, Object?> toJson() => {
    'disposition': disposition.wireName,
    'action': action.wireName,
    'postState': postState.toJson(),
    'effects': effects.map((effect) => effect.toJson()).toList(),
  };
}

abstract final class RealtimeFormalVocabulary {
  static const stateFields = <String>{
    'intent',
    'phase',
    'closeKind',
    'afterClose',
    'activeGeneration',
    'nextGeneration',
    'retryCount',
    'reconnectTimer',
    'heartbeatTimer',
    'disconnectTimer',
    'nextTimerId',
    'pendingHeartbeat',
    'nextHeartbeatRef',
    'hasChannelDemand',
    'started',
  };

  static const eventKinds = <String>{
    'ConnectRequested',
    'DisconnectRequested',
    'ChannelDemandAppeared',
    'ChannelDemandDisappeared',
    'TransportOpened',
    'TransportOpenFailed',
    'TransportErrorObserved',
    'TransportClosed',
    'TransportCloseFailed',
    'HeartbeatSendFailed',
    'ReconnectTimerFired',
    'HeartbeatTimerFired',
    'DisconnectTimerFired',
    'HeartbeatReplyReceived',
  };

  static const actionIds = <String>{
    'startConnect',
    'connectAlreadySatisfied',
    'connectAfterCurrentClose',
    'beginUserClose',
    'retargetCloseToIdle',
    'quiesceWithoutTransport',
    'recordChannelDemand',
    'recordEmptyDemandWithoutTimer',
    'cancelDeferredDisconnect',
    'scheduleDeferredDisconnect',
    'disconnectEmptyDemandNow',
    'channelDemandAlreadyRecorded',
    'acceptTransportOpen',
    'recoverOpenFailure',
    'reportTransportError',
    'settleCloseIdle',
    'settleCloseAndConnect',
    'settleCloseAndBackoff',
    'recoverUnexpectedClose',
    'startReconnectAttempt',
    'sendHeartbeat',
    'timeoutHeartbeat',
    'acceptHeartbeatReply',
    'recoverHeartbeatSendFailure',
    'fireDeferredDisconnect',
    'ignoreStaleTransportEvent',
    'ignoreSupersededOperationEvent',
    'ignoreStaleTimerEvent',
    'ignoreHeartbeatReply',
    'rejectContractViolation',
  };

  static const effectKinds = <String>{
    'OpenTransport',
    'CloseTransport',
    'ArmReconnectTimer',
    'CancelReconnectTimer',
    'ArmHeartbeatTimer',
    'CancelHeartbeatTimer',
    'ArmDisconnectTimer',
    'CancelDisconnectTimer',
    'SendHeartbeat',
    'ResolveCurrentToken',
    'EmitConnectionOpen',
    'EmitConnectionClosed',
    'EmitConnectionError',
    'EmitHeartbeat',
    'NotifyChannelsOfTransportError',
  };

  static const channelEventKinds = <String>{
    'ChannelSubscribeRequested',
    'ChannelManualRejoinRequested',
    'ChannelForceRejoinRequested',
    'ChannelWaitForSocketRequested',
    'ChannelUnsubscribeRequested',
    'ChannelSocketAvailabilityChanged',
    'ChannelJoinReplyReceived',
    'ChannelErrorObserved',
    'ChannelClosedObserved',
    'ChannelRejoinTimerFired',
  };

  static const channelActionIds = <String>{
    'startChannelJoin',
    'subscribeAlreadyActive',
    'beginChannelLeave',
    'channelAlreadyClosed',
    'recordSocketAvailability',
    'acceptJoinReply',
    'rejectJoinAndSchedule',
    'recordChannelError',
    'closeChannel',
    'startChannelRejoin',
    'waitForSocketToRejoin',
    'ignoreStaleChannelEvent',
    'ignoreSupersededJoinEvent',
    'rejectChannelContractViolation',
  };

  static const channelEffectKinds = <String>{
    'SendChannelJoin',
    'SendChannelLeave',
    'ArmChannelRejoinTimer',
    'CancelChannelRejoinTimer',
    'EvictDuplicateChannels',
    'EmitChannelSubscribed',
    'EmitChannelError',
    'EmitChannelClosed',
  };

  static const pushEventKinds = <String>{
    'PushSendRequested',
    'PushPrepareRequested',
    'PushResendRequested',
    'PushReplyReceived',
    'PushTimeoutFired',
    'PushDestroyRequested',
  };

  static const pushActionIds = <String>{
    'startPush',
    'preparePush',
    'sendPreparedPush',
    'resendPush',
    'acceptPushReply',
    'timeoutPush',
    'destroyPush',
    'ignoreStalePushReply',
    'ignoreStalePushTimer',
    'ignorePushAlreadyPending',
    'rejectPushContractViolation',
  };

  static const pushEffectKinds = <String>{
    'BindPushReply',
    'UnbindPushReply',
    'ArmPushTimeoutTimer',
    'CancelPushTimeoutTimer',
    'SendPush',
    'DeliverPushResult',
  };
}
