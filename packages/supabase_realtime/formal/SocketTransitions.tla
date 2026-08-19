---------------------- MODULE SocketTransitions ----------------------
\* Pure socket transition system shared by TLC and the Dart oracle.

EXTENDS KernelSchema, Naturals, FiniteSets, TLC

CONSTANTS
    MaxGeneration,
    MaxTimerId,
    MaxHeartbeatRef,
    MaxRetryCount

GenerationIds == 1..MaxGeneration
GenerationValues == 0..MaxGeneration
TimerIds == 1..MaxTimerId
TimerIdValues == 0..MaxTimerId
HeartbeatRefs == 1..MaxHeartbeatRef
HeartbeatRefValues == 0..MaxHeartbeatRef
RetryCounts == 0..MaxRetryCount
DelayOrdinals == 0..(MaxRetryCount + 1)

NoTimer == [armed |-> FALSE, id |-> 0]
NoReconnectTimer == [armed |-> FALSE, id |-> 0, delayOrdinal |-> 0]
NoGenerationTimer == [armed |-> FALSE, id |-> 0, generation |-> 0]
NoHeartbeatDebt == [active |-> FALSE, generation |-> 0, ref |-> 0]

InitialState ==
    [ intent             |-> "down",
      phase              |-> "idle",
      closeKind          |-> "none",
      afterClose         |-> "none",
      activeGeneration   |-> 0,
      nextGeneration     |-> 1,
      retryCount         |-> 0,
      reconnectTimer     |-> NoReconnectTimer,
      heartbeatTimer     |-> NoGenerationTimer,
      disconnectTimer    |-> NoTimer,
      nextTimerId        |-> 1,
      pendingHeartbeat   |-> NoHeartbeatDebt,
      nextHeartbeatRef   |-> 1,
      hasChannelDemand   |-> FALSE,
      started            |-> FALSE ]

Event(kind) ==
    [ kind            |-> kind,
      generation      |-> 0,
      timerId         |-> 0,
      ref             |-> 0,
      failureKind     |-> "none",
      heartbeatStatus |-> "none",
      grace           |-> "none" ]

Effect(kind) ==
    [ kind            |-> kind,
      generation      |-> 0,
      timerId         |-> 0,
      ref             |-> 0,
      delayOrdinal    |-> 0,
      failureKind     |-> "none",
      heartbeatStatus |-> "none",
      tokenMode       |-> "none",
      closeReason     |-> "none" ]

Result(disposition, action, postState, effects) ==
    [ disposition |-> disposition,
      action      |-> action,
      postState   |-> postState,
      effects     |-> effects ]

OpenTransportEffect(generation) ==
    [Effect("OpenTransport") EXCEPT !.generation = generation]

CloseTransportEffect(generation, reason) ==
    [Effect("CloseTransport") EXCEPT
        !.generation = generation,
        !.closeReason = reason]

ArmReconnectTimerEffect(timerId, delayOrdinal) ==
    [Effect("ArmReconnectTimer") EXCEPT
        !.timerId = timerId,
        !.delayOrdinal = delayOrdinal]

CancelReconnectTimerEffect(timerId) ==
    [Effect("CancelReconnectTimer") EXCEPT !.timerId = timerId]

ArmHeartbeatTimerEffect(timerId, generation) ==
    [Effect("ArmHeartbeatTimer") EXCEPT
        !.timerId = timerId,
        !.generation = generation]

CancelHeartbeatTimerEffect(timerId) ==
    [Effect("CancelHeartbeatTimer") EXCEPT !.timerId = timerId]

ArmDisconnectTimerEffect(timerId) ==
    [Effect("ArmDisconnectTimer") EXCEPT !.timerId = timerId]

CancelDisconnectTimerEffect(timerId) ==
    [Effect("CancelDisconnectTimer") EXCEPT !.timerId = timerId]

SendHeartbeatEffect(generation, ref) ==
    [Effect("SendHeartbeat") EXCEPT
        !.generation = generation,
        !.ref = ref]

ResolveCurrentTokenEffect(tokenMode) ==
    [Effect("ResolveCurrentToken") EXCEPT !.tokenMode = tokenMode]

EmitConnectionOpenEffect == Effect("EmitConnectionOpen")

EmitConnectionClosedEffect(failureKind) ==
    [Effect("EmitConnectionClosed") EXCEPT !.failureKind = failureKind]

EmitConnectionErrorEffect(failureKind) ==
    [Effect("EmitConnectionError") EXCEPT !.failureKind = failureKind]

EmitHeartbeatEffect(status) ==
    [Effect("EmitHeartbeat") EXCEPT !.heartbeatStatus = status]

NotifyChannelsEffect(failureKind) ==
    [Effect("NotifyChannelsOfTransportError") EXCEPT
        !.failureKind = failureKind]

CancelReconnectEffects(s) ==
    IF s.reconnectTimer.armed
    THEN <<CancelReconnectTimerEffect(s.reconnectTimer.id)>>
    ELSE <<>>

CancelHeartbeatEffects(s) ==
    IF s.heartbeatTimer.armed
    THEN <<CancelHeartbeatTimerEffect(s.heartbeatTimer.id)>>
    ELSE <<>>

CancelDisconnectEffects(s) ==
    IF s.disconnectTimer.armed
    THEN <<CancelDisconnectTimerEffect(s.disconnectTimer.id)>>
    ELSE <<>>

CancelAllTimerEffects(s) ==
    CancelReconnectEffects(s)
        \o CancelHeartbeatEffects(s)
        \o CancelDisconnectEffects(s)

NextDelayOrdinal(retryCount) ==
    IF retryCount < MaxRetryCount
    THEN retryCount + 1
    ELSE MaxRetryCount + 1

ConsumeRetry(retryCount) ==
    IF retryCount < MaxRetryCount
    THEN retryCount + 1
    ELSE MaxRetryCount

EventSet ==
    { Event("ConnectRequested"),
      Event("DisconnectRequested"),
      Event("ChannelDemandAppeared") }
    \cup
    { [Event("ChannelDemandDisappeared") EXCEPT !.grace = grace] :
        grace \in GraceKindValues }
    \cup
    { [Event("TransportOpened") EXCEPT !.generation = generation] :
        generation \in GenerationValues }
    \cup
    { Event("TransportOpenFailed") }
    \cup
    { [Event("TransportOpenFailed") EXCEPT
          !.generation = generation,
          !.failureKind = failureKind] :
        generation \in GenerationIds,
        failureKind \in {"sync", "async"} }
    \cup
    { Event("TransportErrorObserved") }
    \cup
    { [Event("TransportErrorObserved") EXCEPT
          !.generation = generation,
          !.failureKind = "stream"] :
        generation \in GenerationIds }
    \cup
    { Event("TransportClosed") }
    \cup
    { [Event("TransportClosed") EXCEPT
          !.generation = generation,
          !.failureKind = failureKind] :
        generation \in GenerationIds,
        failureKind \in {"server", "requested", "timeout"} }
    \cup
    { Event("TransportCloseFailed") }
    \cup
    { [Event("TransportCloseFailed") EXCEPT
          !.generation = generation,
          !.failureKind = failureKind] :
        generation \in GenerationIds,
        failureKind \in {"async", "timeout"} }
    \cup
    { Event("HeartbeatSendFailed") }
    \cup
    { [Event("HeartbeatSendFailed") EXCEPT
          !.generation = generation,
          !.ref = ref,
          !.failureKind = failureKind] :
        generation \in GenerationIds,
        ref \in HeartbeatRefs,
        failureKind \in {"sync", "async", "send"} }
    \cup
    { [Event("ReconnectTimerFired") EXCEPT !.timerId = timerId] :
        timerId \in TimerIdValues }
    \cup
    { [Event("HeartbeatTimerFired") EXCEPT !.timerId = timerId] :
        timerId \in TimerIdValues }
    \cup
    { [Event("DisconnectTimerFired") EXCEPT !.timerId = timerId] :
        timerId \in TimerIdValues }
    \cup
    { Event("HeartbeatReplyReceived") }
    \cup
    { [Event("HeartbeatReplyReceived") EXCEPT
          !.generation = generation,
          !.ref = ref,
          !.heartbeatStatus = status] :
        generation \in GenerationIds,
        ref \in HeartbeatRefs,
        status \in {"ok", "error"} }

ValidEventPayload(e) ==
    CASE e.kind = "ConnectRequested" -> TRUE
      [] e.kind = "DisconnectRequested" -> TRUE
      [] e.kind = "ChannelDemandAppeared" -> TRUE
      [] e.kind = "ChannelDemandDisappeared" ->
            e.grace \in {"zero", "nonzero"}
      [] e.kind = "TransportOpened" ->
            e.generation \in GenerationIds
      [] e.kind = "TransportOpenFailed" ->
            /\ e.generation \in GenerationIds
            /\ e.failureKind \in {"sync", "async"}
      [] e.kind = "TransportErrorObserved" ->
            /\ e.generation \in GenerationIds
            /\ e.failureKind = "stream"
      [] e.kind = "TransportClosed" ->
            /\ e.generation \in GenerationIds
            /\ e.failureKind \in {"server", "requested", "timeout"}
      [] e.kind = "TransportCloseFailed" ->
            /\ e.generation \in GenerationIds
            /\ e.failureKind \in {"async", "timeout"}
      [] e.kind = "HeartbeatSendFailed" ->
            /\ e.generation \in GenerationIds
            /\ e.ref \in HeartbeatRefs
            /\ e.failureKind \in {"sync", "async", "send"}
      [] e.kind \in
            {"ReconnectTimerFired", "HeartbeatTimerFired",
             "DisconnectTimerFired"} ->
            e.timerId \in TimerIds
      [] e.kind = "HeartbeatReplyReceived" ->
            /\ e.generation \in GenerationIds
            /\ e.ref \in HeartbeatRefs
            /\ e.heartbeatStatus \in {"ok", "error"}
      [] OTHER -> FALSE

Ignore(s, action) == Result("ignored", action, s, <<>>)
Reject(s) == Result("rejected", "rejectContractViolation", s, <<>>)

StartConnectState(s, base) ==
    LET generation == s.nextGeneration
    IN [base EXCEPT
          !.phase = "connecting",
          !.closeKind = "none",
          !.afterClose = "none",
          !.activeGeneration = generation,
          !.nextGeneration = generation + 1,
          !.reconnectTimer = NoReconnectTimer,
          !.disconnectTimer = NoTimer,
          !.pendingHeartbeat = NoHeartbeatDebt]

HandleConnectRequested(s) ==
    LET base ==
            [s EXCEPT
                !.intent = "up",
                !.started = TRUE,
                !.retryCount = IF s.intent = "down" THEN 0 ELSE @,
                !.disconnectTimer = NoTimer]
        cancelDisconnect == CancelDisconnectEffects(s)
    IN CASE s.phase = "idle" ->
              LET generation == s.nextGeneration
                  post == StartConnectState(s, base)
              IN Result(
                    "applied",
                    "startConnect",
                    post,
                    cancelDisconnect
                        \o CancelReconnectEffects(s)
                        \o <<OpenTransportEffect(generation)>>)
         [] s.phase \in {"connecting", "open"} ->
              Result(
                  "applied",
                  "connectAlreadySatisfied",
                  base,
                  cancelDisconnect)
         [] s.phase = "closing" ->
              Result(
                  "applied",
                  "connectAfterCurrentClose",
                  [base EXCEPT !.afterClose = "connectNow"],
                  cancelDisconnect)
         [] OTHER -> Reject(s)

DownBase(s) ==
    [s EXCEPT
        !.intent = "down",
        !.retryCount = 0,
        !.reconnectTimer = NoReconnectTimer,
        !.heartbeatTimer = NoGenerationTimer,
        !.disconnectTimer = NoTimer,
        !.pendingHeartbeat = NoHeartbeatDebt]

HandleDisconnect(s, reason, action) ==
    LET base == DownBase(s)
        cancelEffects == CancelAllTimerEffects(s)
    IN CASE s.phase \in {"connecting", "open"} ->
              Result(
                  "applied",
                  action,
                  [base EXCEPT
                      !.phase = "closing",
                      !.closeKind = "user",
                      !.afterClose = "idle"],
                  cancelEffects
                      \o <<CloseTransportEffect(
                              s.activeGeneration,
                              reason)>>)
         [] s.phase = "closing" ->
              Result(
                  "applied",
                  IF action = "fireDeferredDisconnect"
                  THEN action
                  ELSE "retargetCloseToIdle",
                  [base EXCEPT
                      !.closeKind = "user",
                      !.afterClose = "idle"],
                  cancelEffects)
         [] s.phase = "idle" ->
              Result(
                  "applied",
                  IF action = "fireDeferredDisconnect"
                  THEN action
                  ELSE "quiesceWithoutTransport",
                  [base EXCEPT
                      !.closeKind = "none",
                      !.afterClose = "none",
                      !.activeGeneration = 0],
                  cancelEffects)
         [] OTHER -> Reject(s)

HandleChannelDemandAppeared(s) ==
    IF s.hasChannelDemand
    THEN Result(
            "applied",
            "channelDemandAlreadyRecorded",
            s,
            <<>>)
    ELSE LET post ==
                 [s EXCEPT
                     !.hasChannelDemand = TRUE,
                     !.disconnectTimer = NoTimer]
         IN IF s.disconnectTimer.armed
            THEN Result(
                    "applied",
                    "cancelDeferredDisconnect",
                    post,
                    CancelDisconnectEffects(s))
            ELSE Result(
                    "applied",
                    "recordChannelDemand",
                    post,
                    <<>>)

HandleChannelDemandDisappeared(s, e) ==
    IF ~s.hasChannelDemand
    THEN Result(
            "applied",
            "channelDemandAlreadyRecorded",
            s,
            <<>>)
    ELSE LET withoutDemand == [s EXCEPT !.hasChannelDemand = FALSE]
         IN CASE s.intent = "down" ->
                   Result(
                       "applied",
                       "recordEmptyDemandWithoutTimer",
                       [withoutDemand EXCEPT !.disconnectTimer = NoTimer],
                       CancelDisconnectEffects(s))
              [] e.grace = "zero" ->
                   HandleDisconnect(
                       withoutDemand,
                       "emptyChannels",
                       "disconnectEmptyDemandNow")
              [] e.grace = "nonzero" ->
                   LET timerId == s.nextTimerId
                       post ==
                           [withoutDemand EXCEPT
                               !.disconnectTimer =
                                   [armed |-> TRUE, id |-> timerId],
                               !.nextTimerId = timerId + 1]
                   IN Result(
                         "applied",
                         "scheduleDeferredDisconnect",
                         post,
                         CancelDisconnectEffects(s)
                             \o <<ArmDisconnectTimerEffect(timerId)>>)
              [] OTHER -> Reject(s)

HandleTransportOpened(s, e) ==
    IF e.generation # s.activeGeneration
    THEN Ignore(s, "ignoreStaleTransportEvent")
    ELSE IF s.phase # "connecting" \/ s.intent # "up"
    THEN Ignore(s, "ignoreSupersededOperationEvent")
    ELSE LET timerId == s.nextTimerId
             post ==
                 [s EXCEPT
                     !.phase = "open",
                     !.closeKind = "none",
                     !.afterClose = "none",
                     !.retryCount = 0,
                     !.reconnectTimer = NoReconnectTimer,
                     !.heartbeatTimer =
                         [ armed |-> TRUE,
                           id |-> timerId,
                           generation |-> e.generation ],
                     !.nextTimerId = timerId + 1,
                     !.pendingHeartbeat = NoHeartbeatDebt]
         IN Result(
               "applied",
               "acceptTransportOpen",
               post,
               CancelReconnectEffects(s)
                   \o <<ArmHeartbeatTimerEffect(timerId, e.generation),
                        EmitConnectionOpenEffect>>)

HandleTransportOpenFailed(s, e) ==
    IF e.generation # s.activeGeneration
    THEN Ignore(s, "ignoreStaleTransportEvent")
    ELSE IF s.phase # "connecting" \/ s.intent # "up"
    THEN Ignore(s, "ignoreSupersededOperationEvent")
    ELSE LET timerId == s.nextTimerId
             delay == NextDelayOrdinal(s.retryCount)
             post ==
                 [s EXCEPT
                     !.phase = "idle",
                     !.closeKind = "none",
                     !.afterClose = "none",
                     !.activeGeneration = 0,
                     !.reconnectTimer =
                         [ armed |-> TRUE,
                           id |-> timerId,
                           delayOrdinal |-> delay ],
                     !.heartbeatTimer = NoGenerationTimer,
                     !.nextTimerId = timerId + 1,
                     !.pendingHeartbeat = NoHeartbeatDebt]
         IN Result(
               "applied",
               "recoverOpenFailure",
               post,
               <<EmitConnectionErrorEffect(e.failureKind),
                 NotifyChannelsEffect(e.failureKind),
                 ArmReconnectTimerEffect(timerId, delay)>>)

HandleTransportErrorObserved(s, e) ==
    IF e.generation # s.activeGeneration
    THEN Ignore(s, "ignoreStaleTransportEvent")
    ELSE IF s.phase \notin {"connecting", "open", "closing"}
    THEN Reject(s)
    ELSE Result(
            "applied",
            "reportTransportError",
            s,
            <<EmitConnectionErrorEffect(e.failureKind),
              NotifyChannelsEffect(e.failureKind)>>)

ClosedBase(s) ==
    [s EXCEPT
        !.phase = "idle",
        !.closeKind = "none",
        !.afterClose = "none",
        !.activeGeneration = 0,
        !.heartbeatTimer = NoGenerationTimer,
        !.pendingHeartbeat = NoHeartbeatDebt]

CloseOutcomeEffects(s, e) ==
    CancelHeartbeatEffects(s)
        \o (IF e.kind = "TransportCloseFailed"
            THEN <<EmitConnectionErrorEffect(e.failureKind)>>
            ELSE <<>>)
        \o (IF s.closeKind = "recovery"
            THEN <<NotifyChannelsEffect(e.failureKind)>>
            ELSE <<>>)
        \o <<EmitConnectionClosedEffect(e.failureKind)>>

FinalizeCurrentClose(s, e) ==
    LET plan == IF s.intent = "down" THEN "idle" ELSE s.afterClose
        base == ClosedBase(s)
        commonEffects == CloseOutcomeEffects(s, e)
    IN CASE plan = "connectNow" ->
              LET generation == s.nextGeneration
                  post == StartConnectState(s, base)
              IN Result(
                    "applied",
                    "settleCloseAndConnect",
                    post,
                    commonEffects
                        \o CancelReconnectEffects(s)
                        \o <<OpenTransportEffect(generation)>>)
         [] plan = "backoff" ->
              LET timerId == s.nextTimerId
                  delay == NextDelayOrdinal(s.retryCount)
                  post ==
                      [base EXCEPT
                          !.reconnectTimer =
                              [ armed |-> TRUE,
                                id |-> timerId,
                                delayOrdinal |-> delay ],
                          !.nextTimerId = timerId + 1]
              IN Result(
                    "applied",
                    "settleCloseAndBackoff",
                    post,
                    commonEffects
                        \o <<ArmReconnectTimerEffect(timerId, delay)>>)
         [] plan = "idle" ->
              Result(
                  "applied",
                  "settleCloseIdle",
                  [base EXCEPT !.reconnectTimer = NoReconnectTimer],
                  commonEffects \o CancelReconnectEffects(s))
         [] OTHER -> Reject(s)

HandleUnexpectedClose(s, e) ==
    LET base == ClosedBase(s)
        commonEffects ==
            CancelHeartbeatEffects(s)
                \o <<NotifyChannelsEffect(e.failureKind),
                     EmitConnectionClosedEffect(e.failureKind)>>
    IN IF s.intent = "up"
       THEN LET timerId == s.nextTimerId
                delay == NextDelayOrdinal(s.retryCount)
                post ==
                    [base EXCEPT
                        !.reconnectTimer =
                            [ armed |-> TRUE,
                              id |-> timerId,
                              delayOrdinal |-> delay ],
                        !.nextTimerId = timerId + 1]
            IN Result(
                  "applied",
                  "recoverUnexpectedClose",
                  post,
                  commonEffects
                      \o <<ArmReconnectTimerEffect(timerId, delay)>>)
       ELSE Result(
                "applied",
                "settleCloseIdle",
                [base EXCEPT !.reconnectTimer = NoReconnectTimer],
                commonEffects \o CancelReconnectEffects(s))

HandleTransportTerminated(s, e) ==
    IF e.generation # s.activeGeneration
    THEN Ignore(s, "ignoreStaleTransportEvent")
    ELSE CASE s.phase = "closing" -> FinalizeCurrentClose(s, e)
           [] s.phase = "open" /\ e.kind = "TransportClosed" ->
                HandleUnexpectedClose(s, e)
           [] OTHER -> Reject(s)

HandleReconnectTimerFired(s, e) ==
    IF ~s.reconnectTimer.armed \/ e.timerId # s.reconnectTimer.id
    THEN Ignore(s, "ignoreStaleTimerEvent")
    ELSE IF s.intent # "up" \/ s.phase # "idle"
    THEN Reject(s)
    ELSE LET generation == s.nextGeneration
             base ==
                 [s EXCEPT
                     !.retryCount = ConsumeRetry(s.retryCount),
                     !.reconnectTimer = NoReconnectTimer]
             post == StartConnectState(s, base)
         IN Result(
               "applied",
               "startReconnectAttempt",
               post,
               <<OpenTransportEffect(generation)>>)

HandleHeartbeatTimerFired(s, e) ==
    IF ~s.heartbeatTimer.armed \/ e.timerId # s.heartbeatTimer.id
    THEN Ignore(s, "ignoreStaleTimerEvent")
    ELSE IF s.phase # "open"
            \/ s.heartbeatTimer.generation # s.activeGeneration
    THEN Reject(s)
    ELSE IF ~s.pendingHeartbeat.active
    THEN LET ref == s.nextHeartbeatRef
             post ==
                 [s EXCEPT
                     !.pendingHeartbeat =
                         [ active |-> TRUE,
                           generation |-> s.activeGeneration,
                           ref |-> ref ],
                     !.nextHeartbeatRef = ref + 1]
         IN Result(
               "applied",
               "sendHeartbeat",
               post,
               <<SendHeartbeatEffect(s.activeGeneration, ref),
                 EmitHeartbeatEffect("sent"),
                 ResolveCurrentTokenEffect("currentSource")>>)
    ELSE LET post ==
                 [s EXCEPT
                     !.phase = "closing",
                     !.closeKind = "recovery",
                     !.afterClose = "backoff",
                     !.heartbeatTimer = NoGenerationTimer,
                     !.pendingHeartbeat = NoHeartbeatDebt]
         IN Result(
               "applied",
               "timeoutHeartbeat",
               post,
               CancelHeartbeatEffects(s)
                   \o <<EmitHeartbeatEffect("timeout"),
                        CloseTransportEffect(
                            s.activeGeneration,
                            "heartbeatTimeout")>>)

HandleHeartbeatReply(s, e) ==
    IF s.phase = "open"
        /\ s.pendingHeartbeat.active
        /\ e.generation = s.activeGeneration
        /\ e.generation = s.pendingHeartbeat.generation
        /\ e.ref = s.pendingHeartbeat.ref
    THEN Result(
            "applied",
            "acceptHeartbeatReply",
            [s EXCEPT !.pendingHeartbeat = NoHeartbeatDebt],
            <<EmitHeartbeatEffect(e.heartbeatStatus)>>)
    ELSE Ignore(s, "ignoreHeartbeatReply")

HandleHeartbeatSendFailed(s, e) ==
    IF e.generation # s.activeGeneration
    THEN Ignore(s, "ignoreStaleTransportEvent")
    ELSE IF s.phase = "open"
            /\ s.pendingHeartbeat.active
            /\ e.generation = s.pendingHeartbeat.generation
            /\ e.ref = s.pendingHeartbeat.ref
    THEN LET post ==
                 [s EXCEPT
                     !.phase = "closing",
                     !.closeKind = "recovery",
                     !.afterClose = "backoff",
                     !.heartbeatTimer = NoGenerationTimer,
                     !.pendingHeartbeat = NoHeartbeatDebt]
         IN Result(
               "applied",
               "recoverHeartbeatSendFailure",
               post,
               CancelHeartbeatEffects(s)
                   \o <<EmitHeartbeatEffect("error"),
                        EmitConnectionErrorEffect(e.failureKind),
                        NotifyChannelsEffect(e.failureKind),
                        CloseTransportEffect(
                            s.activeGeneration,
                            "transportFailure")>>)
    ELSE Ignore(s, "ignoreHeartbeatReply")

HandleDisconnectTimerFired(s, e) ==
    IF ~s.disconnectTimer.armed \/ e.timerId # s.disconnectTimer.id
    THEN Ignore(s, "ignoreStaleTimerEvent")
    ELSE IF s.hasChannelDemand
    THEN Reject(s)
    ELSE HandleDisconnect(s, "emptyChannels", "fireDeferredDisconnect")

CorrectStep(s, e) ==
    IF ~ValidEventPayload(e)
    THEN Reject(s)
    ELSE CASE e.kind = "ConnectRequested" -> HandleConnectRequested(s)
           [] e.kind = "DisconnectRequested" ->
                HandleDisconnect(s, "userDisconnect", "beginUserClose")
           [] e.kind = "ChannelDemandAppeared" ->
                HandleChannelDemandAppeared(s)
           [] e.kind = "ChannelDemandDisappeared" ->
                HandleChannelDemandDisappeared(s, e)
           [] e.kind = "TransportOpened" ->
                HandleTransportOpened(s, e)
           [] e.kind = "TransportOpenFailed" ->
                HandleTransportOpenFailed(s, e)
           [] e.kind = "TransportErrorObserved" ->
                HandleTransportErrorObserved(s, e)
           [] e.kind \in {"TransportClosed", "TransportCloseFailed"} ->
                HandleTransportTerminated(s, e)
           [] e.kind = "HeartbeatSendFailed" ->
                HandleHeartbeatSendFailed(s, e)
           [] e.kind = "ReconnectTimerFired" ->
                HandleReconnectTimerFired(s, e)
           [] e.kind = "HeartbeatTimerFired" ->
                HandleHeartbeatTimerFired(s, e)
           [] e.kind = "DisconnectTimerFired" ->
                HandleDisconnectTimerFired(s, e)
           [] e.kind = "HeartbeatReplyReceived" ->
                HandleHeartbeatReply(s, e)
           [] OTHER -> Reject(s)

NeedsGeneration(s, e) ==
    ValidEventPayload(e)
    /\ ( \/ e.kind = "ConnectRequested" /\ s.phase = "idle"
         \/ e.kind \in {"TransportClosed", "TransportCloseFailed"}
            /\ e.generation = s.activeGeneration
            /\ s.phase = "closing"
            /\ s.intent = "up"
            /\ s.afterClose = "connectNow"
         \/ e.kind = "ReconnectTimerFired"
            /\ s.reconnectTimer.armed
            /\ e.timerId = s.reconnectTimer.id
            /\ s.intent = "up"
            /\ s.phase = "idle" )

NeedsTimer(s, e) ==
    ValidEventPayload(e)
    /\ ( \/ e.kind = "ChannelDemandDisappeared"
            /\ e.grace = "nonzero"
            /\ s.hasChannelDemand
            /\ s.intent = "up"
         \/ e.kind = "TransportOpened"
            /\ e.generation = s.activeGeneration
            /\ s.phase = "connecting"
            /\ s.intent = "up"
         \/ e.kind = "TransportOpenFailed"
            /\ e.generation = s.activeGeneration
            /\ s.phase = "connecting"
            /\ s.intent = "up"
         \/ e.kind \in {"TransportClosed", "TransportCloseFailed"}
            /\ e.generation = s.activeGeneration
            /\ s.phase = "closing"
            /\ s.intent = "up"
            /\ s.afterClose = "backoff"
         \/ e.kind = "TransportClosed"
            /\ e.generation = s.activeGeneration
            /\ s.phase = "open"
            /\ s.intent = "up" )

NeedsHeartbeatRef(s, e) ==
    ValidEventPayload(e)
    /\ e.kind = "HeartbeatTimerFired"
    /\ s.heartbeatTimer.armed
    /\ e.timerId = s.heartbeatTimer.id
    /\ s.phase = "open"
    /\ s.heartbeatTimer.generation = s.activeGeneration
    /\ ~s.pendingHeartbeat.active

CanStep(s, e) ==
    /\ (~NeedsGeneration(s, e) \/ s.nextGeneration <= MaxGeneration)
    /\ (~NeedsTimer(s, e) \/ s.nextTimerId <= MaxTimerId)
    /\ (~NeedsHeartbeatRef(s, e) \/
            s.nextHeartbeatRef <= MaxHeartbeatRef)

OracleEligible(s) == \A e \in EventSet : CanStep(s, e)

TimerTypeOK(timer) ==
    /\ DOMAIN timer = TimerObligationFields
    /\ timer.armed \in BOOLEAN
    /\ timer.id \in TimerIdValues
    /\ (timer.armed <=> timer.id \in TimerIds)

ReconnectTimerTypeOK(timer) ==
    /\ DOMAIN timer = ReconnectTimerObligationFields
    /\ timer.armed \in BOOLEAN
    /\ timer.id \in TimerIdValues
    /\ timer.delayOrdinal \in DelayOrdinals
    /\ (timer.armed <=> timer.id \in TimerIds)
    /\ (timer.armed <=> timer.delayOrdinal \in 1..(MaxRetryCount + 1))

GenerationTimerTypeOK(timer) ==
    /\ DOMAIN timer = GenerationTimerObligationFields
    /\ timer.armed \in BOOLEAN
    /\ timer.id \in TimerIdValues
    /\ timer.generation \in GenerationValues
    /\ (timer.armed <=> timer.id \in TimerIds)
    /\ (timer.armed <=> timer.generation \in GenerationIds)

HeartbeatDebtTypeOK(debt) ==
    /\ DOMAIN debt = HeartbeatDebtFields
    /\ debt.active \in BOOLEAN
    /\ debt.generation \in GenerationValues
    /\ debt.ref \in HeartbeatRefValues
    /\ (debt.active <=> debt.generation \in GenerationIds)
    /\ (debt.active <=> debt.ref \in HeartbeatRefs)

StateTypeOK(s) ==
    /\ DOMAIN s = SocketModelStateFields
    /\ s.intent \in SocketIntentValues
    /\ s.phase \in SocketPhaseValues
    /\ s.closeKind \in CloseKindValues
    /\ s.afterClose \in AfterCloseValues
    /\ s.activeGeneration \in GenerationValues
    /\ s.nextGeneration \in 1..(MaxGeneration + 1)
    /\ s.retryCount \in RetryCounts
    /\ ReconnectTimerTypeOK(s.reconnectTimer)
    /\ GenerationTimerTypeOK(s.heartbeatTimer)
    /\ TimerTypeOK(s.disconnectTimer)
    /\ s.nextTimerId \in 1..(MaxTimerId + 1)
    /\ HeartbeatDebtTypeOK(s.pendingHeartbeat)
    /\ s.nextHeartbeatRef \in 1..(MaxHeartbeatRef + 1)
    /\ s.hasChannelDemand \in BOOLEAN
    /\ s.started \in BOOLEAN

EventTypeOK(e) ==
    /\ e.kind \in EventKinds
    /\ e.generation \in GenerationValues
    /\ e.timerId \in TimerIdValues
    /\ e.ref \in HeartbeatRefValues
    /\ e.failureKind \in FailureKindValues
    /\ e.heartbeatStatus \in HeartbeatStatusValues
    /\ e.grace \in GraceKindValues

EffectTypeOK(effect) ==
    /\ effect.kind \in EffectKinds
    /\ effect.generation \in GenerationValues
    /\ effect.timerId \in TimerIdValues
    /\ effect.ref \in HeartbeatRefValues
    /\ effect.delayOrdinal \in DelayOrdinals
    /\ effect.failureKind \in FailureKindValues
    /\ effect.heartbeatStatus \in HeartbeatStatusValues
    /\ effect.tokenMode \in TokenModeValues
    /\ effect.closeReason \in CloseReasonValues

ResultTypeOK(result) ==
    /\ result.disposition \in TransitionDispositionValues
    /\ result.action \in ActionIds
    /\ StateTypeOK(result.postState)
    /\ \A index \in 1..Len(result.effects) :
            EffectTypeOK(result.effects[index])

EffectIndices(result, kind) ==
    {index \in 1..Len(result.effects) : result.effects[index].kind = kind}

EffectCount(result, kind) == Cardinality(EffectIndices(result, kind))
HasEffect(result, kind) == EffectCount(result, kind) > 0

TransitionS1(s, e, result) ==
    result.postState.intent = "down" =>
        /\ ~result.postState.reconnectTimer.armed
        /\ ~HasEffect(result, "OpenTransport")

TransitionS2(s, e, result) ==
    /\ (ValidEventPayload(e)
        /\ e.kind = "TransportOpenFailed"
        /\ e.generation = s.activeGeneration
        /\ s.phase = "connecting"
        /\ s.intent = "up") =>
            result.postState.reconnectTimer.armed
    /\ (result.action \in
            {"timeoutHeartbeat", "recoverHeartbeatSendFailure"}) =>
            /\ result.postState.phase = "closing"
            /\ result.postState.closeKind = "recovery"
            /\ result.postState.afterClose = "backoff"
    /\ (ValidEventPayload(e)
        /\ e.kind = "TransportClosed"
        /\ e.generation = s.activeGeneration
        /\ s.phase = "open"
        /\ s.intent = "up") =>
            result.postState.reconnectTimer.armed

StateS3(s) ==
    (s.phase = "idle") <=> (s.activeGeneration = 0)

StateS4(s) ==
    /\ s.heartbeatTimer.armed =>
            /\ s.phase = "open"
            /\ s.heartbeatTimer.generation = s.activeGeneration
    /\ s.pendingHeartbeat.active =>
            /\ s.phase = "open"
            /\ s.pendingHeartbeat.generation = s.activeGeneration

TransitionS5(s, e, result) ==
    /\ \A index \in EffectIndices(result, "ArmReconnectTimer") :
            result.effects[index].delayOrdinal =
                NextDelayOrdinal(s.retryCount)
    /\ result.action = "startReconnectAttempt" =>
            result.postState.retryCount = ConsumeRetry(s.retryCount)

TransitionS6(s, e, result) ==
    result.action = "sendHeartbeat" =>
        /\ EffectCount(result, "ResolveCurrentToken") = 1
        /\ \A index \in EffectIndices(result, "ResolveCurrentToken") :
                result.effects[index].tokenMode = "currentSource"

StateT1(s) ==
    /\ ReconnectTimerTypeOK(s.reconnectTimer)
    /\ GenerationTimerTypeOK(s.heartbeatTimer)
    /\ TimerTypeOK(s.disconnectTimer)

TransitionT2(s, e, result) ==
    result.disposition \in {"ignored", "rejected"} =>
        /\ result.postState = s
        /\ result.effects = <<>>

TransitionT3(s, e, result) ==
    result.action = "acceptTransportOpen" =>
        ~result.postState.pendingHeartbeat.active

TransitionT4(s, e, result) ==
    /\ EffectCount(result, "OpenTransport") <= 1
    /\ EffectCount(result, "CloseTransport") <= 1

StateT5(s) ==
    (s.phase = "idle" /\ s.intent = "down") =>
        /\ s.activeGeneration = 0
        /\ ~s.reconnectTimer.armed
        /\ ~s.heartbeatTimer.armed
        /\ ~s.disconnectTimer.armed
        /\ ~s.pendingHeartbeat.active

StateT6(s) ==
    IF s.phase = "closing"
    THEN /\ s.closeKind \in {"user", "recovery"}
         /\ s.afterClose \in {"idle", "connectNow", "backoff"}
    ELSE /\ s.closeKind = "none"
         /\ s.afterClose = "none"

AllResultsTypeOK(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        /\ EventTypeOK(e)
        /\ CanStep(s, e) => ResultTypeOK(StepOperator(s, e))

AllTransitionS1(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionS1(s, e, StepOperator(s, e))

AllTransitionS2(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionS2(s, e, StepOperator(s, e))

AllTransitionS5(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionS5(s, e, StepOperator(s, e))

AllTransitionS6(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionS6(s, e, StepOperator(s, e))

AllTransitionT2(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionT2(s, e, StepOperator(s, e))

AllTransitionT3(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionT3(s, e, StepOperator(s, e))

AllTransitionT4(s, StepOperator(_, _)) ==
    \A e \in EventSet :
        CanStep(s, e) => TransitionT4(s, e, StepOperator(s, e))

======================================================================
