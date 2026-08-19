------------------------ MODULE KernelSchema ------------------------
\* GENERATED FILE. DO NOT EDIT.
\* Manifest SHA-256: d3c40e1dd47339350cb515eee28726c9ba4f55b563d69ece49a2b7dd5a66912b
\* Schema version: 1

EXTENDS Integers, Sequences

SocketIntentValues == {
    "up",
    "down"
}

SocketPhaseValues == {
    "idle",
    "connecting",
    "open",
    "closing"
}

CloseKindValues == {
    "none",
    "user",
    "recovery"
}

AfterCloseValues == {
    "none",
    "idle",
    "connectNow",
    "backoff"
}

FailureKindValues == {
    "none",
    "sync",
    "async",
    "stream",
    "server",
    "requested",
    "timeout",
    "send"
}

HeartbeatStatusValues == {
    "none",
    "sent",
    "ok",
    "error",
    "timeout"
}

GraceKindValues == {
    "none",
    "zero",
    "nonzero"
}

TransitionDispositionValues == {
    "applied",
    "ignored",
    "rejected"
}

TokenModeValues == {
    "none",
    "currentSource",
    "cachedOverride"
}

CloseReasonValues == {
    "none",
    "userDisconnect",
    "emptyChannels",
    "heartbeatTimeout",
    "transportFailure"
}

ChannelIntentValues == {
    "joined",
    "left"
}

ChannelPhaseValues == {
    "closed",
    "joining",
    "joined",
    "errored",
    "leaving"
}

ReplyStatusValues == {
    "none",
    "ok",
    "error",
    "timeout"
}

PushPhaseValues == {
    "idle",
    "pending",
    "terminal"
}

TimerObligationFields == {
    "armed",
    "id"
}

ReconnectTimerObligationFields == {
    "armed",
    "id",
    "delayOrdinal"
}

GenerationTimerObligationFields == {
    "armed",
    "id",
    "generation"
}

HeartbeatDebtFields == {
    "active",
    "generation",
    "ref"
}

SocketModelStateFields == {
    "intent",
    "phase",
    "closeKind",
    "afterClose",
    "activeGeneration",
    "nextGeneration",
    "retryCount",
    "reconnectTimer",
    "heartbeatTimer",
    "disconnectTimer",
    "nextTimerId",
    "pendingHeartbeat",
    "nextHeartbeatRef",
    "hasChannelDemand",
    "started"
}

EpochTimerObligationFields == {
    "armed",
    "id",
    "epoch"
}

RefTimerObligationFields == {
    "armed",
    "id",
    "ref"
}

ChannelModelStateFields == {
    "channelId",
    "intent",
    "phase",
    "activeJoinEpoch",
    "nextJoinEpoch",
    "rejoinTimer",
    "nextTimerId",
    "socketAvailable",
    "started"
}

PushModelStateFields == {
    "phase",
    "sent",
    "activeRef",
    "nextRef",
    "timeoutTimer",
    "nextTimerId",
    "terminalStatus",
    "terminalDelivered"
}

EventKinds == {
    "ConnectRequested",
    "DisconnectRequested",
    "ChannelDemandAppeared",
    "ChannelDemandDisappeared",
    "TransportOpened",
    "TransportOpenFailed",
    "TransportErrorObserved",
    "TransportClosed",
    "TransportCloseFailed",
    "HeartbeatSendFailed",
    "ReconnectTimerFired",
    "HeartbeatTimerFired",
    "DisconnectTimerFired",
    "HeartbeatReplyReceived"
}

ActionIds == {
    "startConnect",
    "connectAlreadySatisfied",
    "connectAfterCurrentClose",
    "beginUserClose",
    "retargetCloseToIdle",
    "quiesceWithoutTransport",
    "recordChannelDemand",
    "recordEmptyDemandWithoutTimer",
    "cancelDeferredDisconnect",
    "scheduleDeferredDisconnect",
    "disconnectEmptyDemandNow",
    "channelDemandAlreadyRecorded",
    "acceptTransportOpen",
    "recoverOpenFailure",
    "reportTransportError",
    "settleCloseIdle",
    "settleCloseAndConnect",
    "settleCloseAndBackoff",
    "recoverUnexpectedClose",
    "startReconnectAttempt",
    "sendHeartbeat",
    "timeoutHeartbeat",
    "acceptHeartbeatReply",
    "recoverHeartbeatSendFailure",
    "fireDeferredDisconnect",
    "ignoreStaleTransportEvent",
    "ignoreSupersededOperationEvent",
    "ignoreStaleTimerEvent",
    "ignoreHeartbeatReply",
    "rejectContractViolation"
}

EffectKinds == {
    "OpenTransport",
    "CloseTransport",
    "ArmReconnectTimer",
    "CancelReconnectTimer",
    "ArmHeartbeatTimer",
    "CancelHeartbeatTimer",
    "ArmDisconnectTimer",
    "CancelDisconnectTimer",
    "SendHeartbeat",
    "ResolveCurrentToken",
    "EmitConnectionOpen",
    "EmitConnectionClosed",
    "EmitConnectionError",
    "EmitHeartbeat",
    "NotifyChannelsOfTransportError"
}

ChannelEventKinds == {
    "ChannelSubscribeRequested",
    "ChannelManualRejoinRequested",
    "ChannelForceRejoinRequested",
    "ChannelWaitForSocketRequested",
    "ChannelUnsubscribeRequested",
    "ChannelSocketAvailabilityChanged",
    "ChannelJoinReplyReceived",
    "ChannelErrorObserved",
    "ChannelClosedObserved",
    "ChannelRejoinTimerFired"
}

ChannelActionIds == {
    "startChannelJoin",
    "subscribeAlreadyActive",
    "beginChannelLeave",
    "channelAlreadyClosed",
    "recordSocketAvailability",
    "acceptJoinReply",
    "rejectJoinAndSchedule",
    "recordChannelError",
    "closeChannel",
    "startChannelRejoin",
    "waitForSocketToRejoin",
    "ignoreStaleChannelEvent",
    "ignoreSupersededJoinEvent",
    "rejectChannelContractViolation"
}

ChannelEffectKinds == {
    "SendChannelJoin",
    "SendChannelLeave",
    "ArmChannelRejoinTimer",
    "CancelChannelRejoinTimer",
    "EvictDuplicateChannels",
    "EmitChannelSubscribed",
    "EmitChannelError",
    "EmitChannelClosed"
}

PushEventKinds == {
    "PushSendRequested",
    "PushPrepareRequested",
    "PushResendRequested",
    "PushReplyReceived",
    "PushTimeoutFired",
    "PushDestroyRequested"
}

PushActionIds == {
    "startPush",
    "preparePush",
    "sendPreparedPush",
    "resendPush",
    "acceptPushReply",
    "timeoutPush",
    "destroyPush",
    "ignoreStalePushReply",
    "ignoreStalePushTimer",
    "ignorePushAlreadyPending",
    "rejectPushContractViolation"
}

PushEffectKinds == {
    "BindPushReply",
    "UnbindPushReply",
    "ArmPushTimeoutTimer",
    "CancelPushTimeoutTimer",
    "SendPush",
    "DeliverPushResult"
}

TraceRequiredFields == {
    "schemaHash",
    "modelHash",
    "machine",
    "instance",
    "sequence",
    "event",
    "action",
    "disposition",
    "preState",
    "postState",
    "effects"
}

TraceIdentityFields == {
    "activeGeneration",
    "nextGeneration",
    "generation",
    "timerId",
    "id",
    "ref",
    "nextTimerId",
    "nextHeartbeatRef",
    "channelId",
    "requesterChannelId",
    "activeJoinEpoch",
    "nextJoinEpoch",
    "epoch",
    "activeRef",
    "nextRef"
}

ManifestSchemaVersion == 1
ManifestSha256 == "d3c40e1dd47339350cb515eee28726c9ba4f55b563d69ece49a2b7dd5a66912b"

=====================================================================
