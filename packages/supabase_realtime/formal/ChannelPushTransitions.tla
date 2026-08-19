------------------- MODULE ChannelPushTransitions -------------------
\* Pure channel and push lifecycle kernels.

EXTENDS KernelSchema, Naturals, FiniteSets, TLC

CONSTANTS
    MaxChannelId,
    MaxJoinEpoch,
    MaxTimerId,
    MaxPushRef

ChannelIds == 1..MaxChannelId
JoinEpochs == 1..MaxJoinEpoch
JoinEpochValues == 0..MaxJoinEpoch
TimerIds == 1..MaxTimerId
TimerIdValues == 0..MaxTimerId
PushRefs == 1..MaxPushRef
PushRefValues == 0..MaxPushRef

NoEpochTimer == [armed |-> FALSE, id |-> 0, epoch |-> 0]
NoRefTimer == [armed |-> FALSE, id |-> 0, ref |-> 0]

InitialChannelState(channelId) ==
    [ channelId        |-> channelId,
      intent           |-> "left",
      phase            |-> "closed",
      activeJoinEpoch  |-> 0,
      nextJoinEpoch    |-> 1,
      rejoinTimer      |-> NoEpochTimer,
      nextTimerId      |-> 1,
      socketAvailable  |-> FALSE,
      started          |-> FALSE ]

InitialPushState ==
    [ phase             |-> "idle",
      sent              |-> FALSE,
      activeRef         |-> 0,
      nextRef           |-> 1,
      timeoutTimer      |-> NoRefTimer,
      nextTimerId       |-> 1,
      terminalStatus    |-> "none",
      terminalDelivered |-> FALSE ]

ChannelEvent(kind) ==
    [ kind        |-> kind,
      available   |-> FALSE,
      epoch       |-> 0,
      replyStatus |-> "none",
      timerId     |-> 0 ]

ChannelEffect(kind) ==
    [ kind               |-> kind,
      epoch              |-> 0,
      timerId            |-> 0,
      requesterChannelId |-> 0,
      replyStatus        |-> "none" ]

ChannelResult(disposition, action, postState, effects) ==
    [ disposition |-> disposition,
      action      |-> action,
      postState   |-> postState,
      effects     |-> effects ]

PushEvent(kind) ==
    [ kind        |-> kind,
      ref         |-> 0,
      replyStatus |-> "none",
      timerId     |-> 0 ]

PushEffect(kind) ==
    [ kind        |-> kind,
      ref         |-> 0,
      replyStatus |-> "none",
      timerId     |-> 0 ]

PushResult(disposition, action, postState, effects) ==
    [ disposition |-> disposition,
      action      |-> action,
      postState   |-> postState,
      effects     |-> effects ]

SendChannelJoinEffect(epoch) ==
    [ChannelEffect("SendChannelJoin") EXCEPT !.epoch = epoch]

SendChannelLeaveEffect(epoch) ==
    [ChannelEffect("SendChannelLeave") EXCEPT !.epoch = epoch]

ArmChannelRejoinTimerEffect(timerId, epoch) ==
    [ChannelEffect("ArmChannelRejoinTimer") EXCEPT
        !.timerId = timerId,
        !.epoch = epoch]

CancelChannelRejoinTimerEffect(timerId) ==
    [ChannelEffect("CancelChannelRejoinTimer") EXCEPT !.timerId = timerId]

EvictDuplicateChannelsEffect(requesterChannelId) ==
    [ChannelEffect("EvictDuplicateChannels") EXCEPT
        !.requesterChannelId = requesterChannelId]

EmitChannelSubscribedEffect == ChannelEffect("EmitChannelSubscribed")

EmitChannelErrorEffect(status) ==
    [ChannelEffect("EmitChannelError") EXCEPT !.replyStatus = status]

EmitChannelClosedEffect == ChannelEffect("EmitChannelClosed")

BindPushReplyEffect(ref) ==
    [PushEffect("BindPushReply") EXCEPT !.ref = ref]

UnbindPushReplyEffect(ref) ==
    [PushEffect("UnbindPushReply") EXCEPT !.ref = ref]

ArmPushTimeoutTimerEffect(timerId, ref) ==
    [PushEffect("ArmPushTimeoutTimer") EXCEPT
        !.timerId = timerId,
        !.ref = ref]

CancelPushTimeoutTimerEffect(timerId) ==
    [PushEffect("CancelPushTimeoutTimer") EXCEPT !.timerId = timerId]

SendPushEffect(ref) == [PushEffect("SendPush") EXCEPT !.ref = ref]

DeliverPushResultEffect(ref, status) ==
    [PushEffect("DeliverPushResult") EXCEPT
        !.ref = ref,
        !.replyStatus = status]

CancelChannelTimerEffects(s) ==
    IF s.rejoinTimer.armed
    THEN <<CancelChannelRejoinTimerEffect(s.rejoinTimer.id)>>
    ELSE <<>>

CancelPushEffects(s) ==
    IF s.phase = "pending"
    THEN <<UnbindPushReplyEffect(s.activeRef),
           CancelPushTimeoutTimerEffect(s.timeoutTimer.id)>>
    ELSE <<>>

ChannelEventSet ==
    { ChannelEvent("ChannelSubscribeRequested"),
      ChannelEvent("ChannelManualRejoinRequested"),
      ChannelEvent("ChannelForceRejoinRequested"),
      ChannelEvent("ChannelWaitForSocketRequested"),
      ChannelEvent("ChannelUnsubscribeRequested") }
    \cup
    { [ChannelEvent("ChannelSocketAvailabilityChanged") EXCEPT
          !.available = available] : available \in BOOLEAN }
    \cup
    { ChannelEvent("ChannelJoinReplyReceived") }
    \cup
    { [ChannelEvent("ChannelJoinReplyReceived") EXCEPT
          !.epoch = epoch,
          !.replyStatus = status] :
        epoch \in JoinEpochs,
        status \in {"ok", "error", "timeout"} }
    \cup
    { ChannelEvent("ChannelErrorObserved") }
    \cup
    { [ChannelEvent("ChannelErrorObserved") EXCEPT !.epoch = epoch] :
        epoch \in JoinEpochValues }
    \cup
    { ChannelEvent("ChannelClosedObserved") }
    \cup
    { [ChannelEvent("ChannelClosedObserved") EXCEPT !.epoch = epoch] :
        epoch \in JoinEpochValues }
    \cup
    { [ChannelEvent("ChannelRejoinTimerFired") EXCEPT !.timerId = timerId] :
        timerId \in TimerIdValues }

PushEventSet ==
    { PushEvent("PushSendRequested"),
      PushEvent("PushPrepareRequested"),
      PushEvent("PushResendRequested"),
      PushEvent("PushDestroyRequested"),
      PushEvent("PushReplyReceived") }
    \cup
    { [PushEvent("PushReplyReceived") EXCEPT
          !.ref = ref,
          !.replyStatus = status] :
        ref \in PushRefs,
        status \in {"ok", "error"} }
    \cup
    { [PushEvent("PushTimeoutFired") EXCEPT !.timerId = timerId] :
        timerId \in TimerIdValues }

ValidChannelEvent(e) ==
    CASE e.kind \in
            {"ChannelSubscribeRequested", "ChannelManualRejoinRequested",
             "ChannelForceRejoinRequested",
             "ChannelWaitForSocketRequested",
             "ChannelUnsubscribeRequested"} ->
                TRUE
      [] e.kind = "ChannelSocketAvailabilityChanged" ->
                e.available \in BOOLEAN
      [] e.kind = "ChannelJoinReplyReceived" ->
                /\ e.epoch \in JoinEpochs
                /\ e.replyStatus \in {"ok", "error", "timeout"}
      [] e.kind \in {"ChannelErrorObserved", "ChannelClosedObserved"} ->
                e.epoch \in JoinEpochs
      [] e.kind = "ChannelRejoinTimerFired" ->
                e.timerId \in TimerIds
      [] OTHER -> FALSE

ValidPushEvent(e) ==
    CASE e.kind \in
            {"PushSendRequested", "PushPrepareRequested",
             "PushResendRequested",
             "PushDestroyRequested"} -> TRUE
      [] e.kind = "PushReplyReceived" ->
                /\ e.ref \in PushRefs
                /\ e.replyStatus \in {"ok", "error"}
      [] e.kind = "PushTimeoutFired" -> e.timerId \in TimerIds
      [] OTHER -> FALSE

IgnoreChannel(s, action) ==
    ChannelResult("ignored", action, s, <<>>)

RejectChannel(s) ==
    ChannelResult("rejected", "rejectChannelContractViolation", s, <<>>)

IgnorePush(s, action) == PushResult("ignored", action, s, <<>>)
RejectPush(s) == PushResult("rejected", "rejectPushContractViolation", s, <<>>)

StartChannelJoin(s, action, prefix) ==
    LET epoch == s.nextJoinEpoch
        post == [s EXCEPT
                    !.phase = "joining",
                    !.activeJoinEpoch = epoch,
                    !.nextJoinEpoch = epoch + 1,
                    !.rejoinTimer = NoEpochTimer]
    IN ChannelResult(
         "applied",
         action,
         post,
         prefix \o <<SendChannelJoinEffect(epoch)>>)

ArmChannelRejoin(s, action, status, emitError) ==
    LET timerId == s.nextTimerId
        post == [s EXCEPT
                    !.rejoinTimer =
                        [ armed |-> TRUE,
                          id |-> timerId,
                          epoch |-> s.activeJoinEpoch ],
                    !.nextTimerId = timerId + 1]
        errorEffects ==
            IF emitError THEN <<EmitChannelErrorEffect(status)>> ELSE <<>>
    IN ChannelResult(
         "applied",
         action,
         post,
         CancelChannelTimerEffects(s)
             \o errorEffects
             \o <<ArmChannelRejoinTimerEffect(
                    timerId,
                    s.activeJoinEpoch)>>)

FailChannelAndSchedule(s, action, status) ==
    ArmChannelRejoin(
        [s EXCEPT !.phase = "errored"],
        action,
        status,
        TRUE)

HandleChannelSubscribe(s) ==
    IF /\ s.intent = "joined"
       /\ s.phase \in {"joining", "joined"}
    THEN ChannelResult("applied", "subscribeAlreadyActive", s, <<>>)
    ELSE IF s.phase = "leaving"
    THEN RejectChannel(s)
    ELSE LET base == [s EXCEPT !.intent = "joined", !.started = TRUE]
         IN StartChannelJoin(
              base,
              "startChannelJoin",
              CancelChannelTimerEffects(s)
                  \o <<EvictDuplicateChannelsEffect(s.channelId)>>)

HandleChannelManualRejoin(s, evictDuplicates) ==
    IF s.phase = "leaving"
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE LET base == [s EXCEPT !.intent = "joined", !.started = TRUE]
             evictEffects ==
                IF evictDuplicates
                THEN <<EvictDuplicateChannelsEffect(s.channelId)>>
                ELSE <<>>
         IN StartChannelJoin(
              base,
              "startChannelJoin",
              CancelChannelTimerEffects(s) \o evictEffects)

HandleChannelWaitForSocket(s) ==
    IF s.phase = "leaving"
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE IF s.socketAvailable
    THEN HandleChannelManualRejoin(s, TRUE)
    ELSE LET epoch ==
                IF s.activeJoinEpoch > 0
                THEN s.activeJoinEpoch
                ELSE s.nextJoinEpoch
             allocatesEpoch == s.activeJoinEpoch = 0
             waiting ==
                [s EXCEPT
                    !.intent = "joined",
                    !.phase = "errored",
                    !.activeJoinEpoch = epoch,
                    !.nextJoinEpoch =
                        IF allocatesEpoch THEN epoch + 1 ELSE @,
                    !.started = TRUE]
         IN ArmChannelRejoin(
              waiting,
              "waitForSocketToRejoin",
              "error",
              FALSE)

HandleChannelUnsubscribe(s) ==
    IF s.phase = "closed" \/ s.intent = "left"
    THEN ChannelResult(
           "applied",
           "channelAlreadyClosed",
           [s EXCEPT
               !.intent = "left",
               !.phase = "closed",
               !.activeJoinEpoch = 0,
               !.rejoinTimer = NoEpochTimer],
           CancelChannelTimerEffects(s)
               \o <<EmitChannelClosedEffect>>)
    ELSE IF s.phase = "leaving"
    THEN ChannelResult("applied", "channelAlreadyClosed", s, <<>>)
    ELSE ChannelResult(
           "applied",
           "beginChannelLeave",
           [s EXCEPT
               !.intent = "left",
               !.phase = "leaving",
               !.rejoinTimer = NoEpochTimer],
           CancelChannelTimerEffects(s)
               \o <<SendChannelLeaveEffect(s.activeJoinEpoch)>>)

HandleChannelSocketAvailability(s, e) ==
    ChannelResult(
        "applied",
        "recordSocketAvailability",
        [s EXCEPT !.socketAvailable = e.available],
        <<>>)

HandleChannelJoinReply(s, e) ==
    IF e.epoch # s.activeJoinEpoch
    THEN IgnoreChannel(s, "ignoreStaleChannelEvent")
    ELSE IF s.phase \in {"leaving", "closed"}
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE IF s.phase = "errored"
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE IF s.phase # "joining"
    THEN RejectChannel(s)
    ELSE IF e.replyStatus = "ok"
    THEN ChannelResult(
           "applied",
           "acceptJoinReply",
           [s EXCEPT !.phase = "joined", !.rejoinTimer = NoEpochTimer],
           CancelChannelTimerEffects(s)
               \o <<EmitChannelSubscribedEffect>>)
    ELSE FailChannelAndSchedule(
           s,
           "rejectJoinAndSchedule",
           e.replyStatus)

HandleChannelError(s, e) ==
    IF e.epoch # s.activeJoinEpoch
    THEN IgnoreChannel(s, "ignoreStaleChannelEvent")
    ELSE IF s.phase \in {"leaving", "closed"}
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE IF s.phase = "errored"
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE IF s.phase \notin {"joining", "joined"}
    THEN RejectChannel(s)
    ELSE FailChannelAndSchedule(s, "recordChannelError", "error")

HandleChannelClosed(s, e) ==
    IF e.epoch # s.activeJoinEpoch
    THEN IgnoreChannel(s, "ignoreStaleChannelEvent")
    ELSE IF s.phase = "closed"
    THEN IgnoreChannel(s, "ignoreSupersededJoinEvent")
    ELSE ChannelResult(
           "applied",
           "closeChannel",
           [s EXCEPT
               !.intent = "left",
               !.phase = "closed",
               !.activeJoinEpoch = 0,
               !.rejoinTimer = NoEpochTimer],
           CancelChannelTimerEffects(s)
               \o <<EmitChannelClosedEffect>>)

HandleChannelRejoinTimer(s, e) ==
    IF ~s.rejoinTimer.armed \/ e.timerId # s.rejoinTimer.id
    THEN IgnoreChannel(s, "ignoreStaleChannelEvent")
    ELSE IF s.intent # "joined"
            \/ s.phase # "errored"
            \/ s.rejoinTimer.epoch # s.activeJoinEpoch
    THEN RejectChannel(s)
    ELSE LET disarmed == [s EXCEPT !.rejoinTimer = NoEpochTimer]
         IN IF s.socketAvailable
            THEN StartChannelJoin(
                   disarmed,
                   "startChannelRejoin",
                   <<CancelChannelRejoinTimerEffect(s.rejoinTimer.id),
                     EvictDuplicateChannelsEffect(s.channelId)>>)
            ELSE ArmChannelRejoin(
                   disarmed,
                   "waitForSocketToRejoin",
                   "error",
                   FALSE)

CorrectChannelStep(s, e) ==
    IF ~ValidChannelEvent(e)
    THEN RejectChannel(s)
    ELSE CASE e.kind = "ChannelSubscribeRequested" ->
                HandleChannelSubscribe(s)
           [] e.kind = "ChannelManualRejoinRequested" ->
                HandleChannelManualRejoin(s, TRUE)
           [] e.kind = "ChannelForceRejoinRequested" ->
                HandleChannelManualRejoin(s, FALSE)
           [] e.kind = "ChannelWaitForSocketRequested" ->
                HandleChannelWaitForSocket(s)
           [] e.kind = "ChannelUnsubscribeRequested" ->
                HandleChannelUnsubscribe(s)
           [] e.kind = "ChannelSocketAvailabilityChanged" ->
                HandleChannelSocketAvailability(s, e)
           [] e.kind = "ChannelJoinReplyReceived" ->
                HandleChannelJoinReply(s, e)
           [] e.kind = "ChannelErrorObserved" ->
                HandleChannelError(s, e)
           [] e.kind = "ChannelClosedObserved" ->
                HandleChannelClosed(s, e)
           [] e.kind = "ChannelRejoinTimerFired" ->
                HandleChannelRejoinTimer(s, e)
           [] OTHER -> RejectChannel(s)

StartPush(s, action, prefix, send) ==
    LET ref == s.nextRef
        timerId == s.nextTimerId
        post == [s EXCEPT
                    !.phase = "pending",
                    !.sent = send,
                    !.activeRef = ref,
                    !.nextRef = ref + 1,
                    !.timeoutTimer =
                        [armed |-> TRUE, id |-> timerId, ref |-> ref],
                    !.nextTimerId = timerId + 1,
                    !.terminalStatus = "none",
                    !.terminalDelivered = FALSE]
    IN PushResult(
         "applied",
         action,
         post,
         prefix
             \o <<BindPushReplyEffect(ref),
                  ArmPushTimeoutTimerEffect(timerId, ref)>>
             \o (IF send THEN <<SendPushEffect(ref)>> ELSE <<>>))

HandlePushSend(s) ==
    IF s.phase = "pending"
    THEN IF s.sent
         THEN IgnorePush(s, "ignorePushAlreadyPending")
         ELSE PushResult(
                "applied",
                "sendPreparedPush",
                [s EXCEPT !.sent = TRUE],
                <<SendPushEffect(s.activeRef)>>)
    ELSE IF s.phase = "terminal"
    THEN RejectPush(s)
    ELSE StartPush(s, "startPush", <<>>, TRUE)

HandlePushPrepare(s) ==
    IF s.phase = "pending"
    THEN IgnorePush(s, "ignorePushAlreadyPending")
    ELSE IF s.phase = "terminal"
    THEN RejectPush(s)
    ELSE StartPush(s, "preparePush", <<>>, FALSE)

HandlePushResend(s) ==
    StartPush(s, "resendPush", CancelPushEffects(s), TRUE)

TerminalPush(s, action, status) ==
    PushResult(
        "applied",
        action,
        [s EXCEPT
            !.phase = "terminal",
            !.timeoutTimer = NoRefTimer,
            !.terminalStatus = status,
            !.terminalDelivered = TRUE],
        <<UnbindPushReplyEffect(s.activeRef),
          CancelPushTimeoutTimerEffect(s.timeoutTimer.id),
          DeliverPushResultEffect(s.activeRef, status)>>)

HandlePushReply(s, e) ==
    IF s.phase # "pending" \/ e.ref # s.activeRef
    THEN IgnorePush(s, "ignoreStalePushReply")
    ELSE TerminalPush(s, "acceptPushReply", e.replyStatus)

HandlePushTimeout(s, e) ==
    IF ~s.timeoutTimer.armed \/ e.timerId # s.timeoutTimer.id
    THEN IgnorePush(s, "ignoreStalePushTimer")
    ELSE IF s.phase # "pending" \/ s.timeoutTimer.ref # s.activeRef
    THEN RejectPush(s)
    ELSE TerminalPush(s, "timeoutPush", "timeout")

HandlePushDestroy(s) ==
    PushResult(
        "applied",
        "destroyPush",
        [s EXCEPT
            !.phase = "idle",
            !.sent = FALSE,
            !.activeRef = 0,
            !.timeoutTimer = NoRefTimer,
            !.terminalStatus = "none",
            !.terminalDelivered = FALSE],
        CancelPushEffects(s))

CorrectPushStep(s, e) ==
    IF ~ValidPushEvent(e)
    THEN RejectPush(s)
    ELSE CASE e.kind = "PushSendRequested" -> HandlePushSend(s)
           [] e.kind = "PushPrepareRequested" -> HandlePushPrepare(s)
           [] e.kind = "PushResendRequested" -> HandlePushResend(s)
           [] e.kind = "PushReplyReceived" -> HandlePushReply(s, e)
           [] e.kind = "PushTimeoutFired" -> HandlePushTimeout(s, e)
           [] e.kind = "PushDestroyRequested" -> HandlePushDestroy(s)
           [] OTHER -> RejectPush(s)

NeedsChannelEpoch(s, e) ==
    ValidChannelEvent(e)
    /\ ( \/ e.kind = "ChannelSubscribeRequested"
            /\ ~(s.intent = "joined" /\ s.phase \in {"joining", "joined"})
            /\ s.phase # "leaving"
         \/ e.kind \in
                {"ChannelManualRejoinRequested",
                 "ChannelForceRejoinRequested"}
            /\ s.phase # "leaving"
         \/ e.kind = "ChannelWaitForSocketRequested"
            /\ s.phase # "leaving"
            /\ (s.socketAvailable \/ s.activeJoinEpoch = 0)
         \/ e.kind = "ChannelRejoinTimerFired"
            /\ s.rejoinTimer.armed
            /\ e.timerId = s.rejoinTimer.id
            /\ s.intent = "joined"
            /\ s.phase = "errored"
            /\ s.rejoinTimer.epoch = s.activeJoinEpoch
            /\ s.socketAvailable )

NeedsChannelTimer(s, e) ==
    ValidChannelEvent(e)
    /\ ( \/ e.kind \in
                {"ChannelWaitForSocketRequested"}
            /\ s.phase # "leaving"
            /\ ~s.socketAvailable
         \/ e.kind = "ChannelJoinReplyReceived"
            /\ e.epoch = s.activeJoinEpoch
            /\ s.phase = "joining"
            /\ e.replyStatus \in {"error", "timeout"}
         \/ e.kind = "ChannelErrorObserved"
            /\ e.epoch = s.activeJoinEpoch
            /\ s.phase \in {"joining", "joined"}
         \/ e.kind = "ChannelClosedObserved"
            /\ e.epoch = s.activeJoinEpoch
            /\ s.intent = "joined"
            /\ s.phase \notin {"closed", "leaving"}
         \/ e.kind = "ChannelRejoinTimerFired"
            /\ s.rejoinTimer.armed
            /\ e.timerId = s.rejoinTimer.id
            /\ s.intent = "joined"
            /\ s.phase = "errored"
            /\ ~s.socketAvailable )

CanChannelStep(s, e) ==
    /\ (~NeedsChannelEpoch(s, e) \/ s.nextJoinEpoch <= MaxJoinEpoch)
    /\ (~NeedsChannelTimer(s, e) \/ s.nextTimerId <= MaxTimerId)

NeedsPushAllocation(s, e) ==
    ValidPushEvent(e)
    /\ ( \/ e.kind = "PushSendRequested" /\ s.phase = "idle"
         \/ e.kind = "PushPrepareRequested" /\ s.phase = "idle"
         \/ e.kind = "PushResendRequested" )

CanPushStep(s, e) ==
    ~NeedsPushAllocation(s, e)
    \/ (s.nextRef <= MaxPushRef /\ s.nextTimerId <= MaxTimerId)

EpochTimerTypeOK(timer) ==
    /\ DOMAIN timer = EpochTimerObligationFields
    /\ timer.armed \in BOOLEAN
    /\ timer.id \in TimerIdValues
    /\ timer.epoch \in JoinEpochValues
    /\ (timer.armed <=> timer.id \in TimerIds)
    /\ (timer.armed <=> timer.epoch \in JoinEpochs)

RefTimerTypeOK(timer) ==
    /\ DOMAIN timer = RefTimerObligationFields
    /\ timer.armed \in BOOLEAN
    /\ timer.id \in TimerIdValues
    /\ timer.ref \in PushRefValues
    /\ (timer.armed <=> timer.id \in TimerIds)
    /\ (timer.armed <=> timer.ref \in PushRefs)

ChannelStateTypeOK(s) ==
    /\ DOMAIN s = ChannelModelStateFields
    /\ s.channelId \in ChannelIds
    /\ s.intent \in ChannelIntentValues
    /\ s.phase \in ChannelPhaseValues
    /\ s.activeJoinEpoch \in JoinEpochValues
    /\ s.nextJoinEpoch \in 1..(MaxJoinEpoch + 1)
    /\ EpochTimerTypeOK(s.rejoinTimer)
    /\ s.nextTimerId \in 1..(MaxTimerId + 1)
    /\ s.socketAvailable \in BOOLEAN
    /\ s.started \in BOOLEAN

PushStateTypeOK(s) ==
    /\ DOMAIN s = PushModelStateFields
    /\ s.phase \in PushPhaseValues
    /\ s.sent \in BOOLEAN
    /\ s.activeRef \in PushRefValues
    /\ s.nextRef \in 1..(MaxPushRef + 1)
    /\ RefTimerTypeOK(s.timeoutTimer)
    /\ s.nextTimerId \in 1..(MaxTimerId + 1)
    /\ s.terminalStatus \in ReplyStatusValues
    /\ s.terminalDelivered \in BOOLEAN

ChannelEventTypeOK(e) ==
    /\ e.kind \in ChannelEventKinds
    /\ e.available \in BOOLEAN
    /\ e.epoch \in JoinEpochValues
    /\ e.replyStatus \in ReplyStatusValues
    /\ e.timerId \in TimerIdValues

PushEventTypeOK(e) ==
    /\ e.kind \in PushEventKinds
    /\ e.ref \in PushRefValues
    /\ e.replyStatus \in ReplyStatusValues
    /\ e.timerId \in TimerIdValues

ChannelEffectTypeOK(effect) ==
    /\ effect.kind \in ChannelEffectKinds
    /\ effect.epoch \in JoinEpochValues
    /\ effect.timerId \in TimerIdValues
    /\ effect.requesterChannelId \in 0..MaxChannelId
    /\ effect.replyStatus \in ReplyStatusValues

PushEffectTypeOK(effect) ==
    /\ effect.kind \in PushEffectKinds
    /\ effect.ref \in PushRefValues
    /\ effect.replyStatus \in ReplyStatusValues
    /\ effect.timerId \in TimerIdValues

ChannelResultTypeOK(result) ==
    /\ result.disposition \in TransitionDispositionValues
    /\ result.action \in ChannelActionIds
    /\ ChannelStateTypeOK(result.postState)
    /\ \A index \in 1..Len(result.effects) :
            ChannelEffectTypeOK(result.effects[index])

PushResultTypeOK(result) ==
    /\ result.disposition \in TransitionDispositionValues
    /\ result.action \in PushActionIds
    /\ PushStateTypeOK(result.postState)
    /\ \A index \in 1..Len(result.effects) :
            PushEffectTypeOK(result.effects[index])

ChannelEffectIndices(result, kind) ==
    {index \in 1..Len(result.effects) : result.effects[index].kind = kind}

PushEffectIndices(result, kind) ==
    {index \in 1..Len(result.effects) : result.effects[index].kind = kind}

ChannelEffectCount(result, kind) ==
    Cardinality(ChannelEffectIndices(result, kind))

PushEffectCount(result, kind) ==
    Cardinality(PushEffectIndices(result, kind))

StateC1(s) ==
    s.phase = "errored" =>
        /\ s.intent = "joined"
        /\ s.rejoinTimer.armed

TransitionC1(s, e, result) ==
    ( /\ ValidChannelEvent(e)
      /\ e.kind = "ChannelJoinReplyReceived"
      /\ e.epoch = s.activeJoinEpoch
      /\ s.phase = "joining"
      /\ e.replyStatus \in {"error", "timeout"} ) =>
        /\ result.postState.phase = "errored"
        /\ result.postState.rejoinTimer.armed

StateC2(s) ==
    s.rejoinTimer.armed =>
        /\ s.intent = "joined"
        /\ s.phase = "errored"
        /\ s.rejoinTimer.epoch = s.activeJoinEpoch

TransitionC2(s, e, result) ==
    ( /\ e.kind = "ChannelRejoinTimerFired"
      /\ s.rejoinTimer.armed
      /\ e.timerId = s.rejoinTimer.id
      /\ s.socketAvailable ) =>
        /\ ~result.postState.rejoinTimer.armed
        /\ result.action = "startChannelRejoin"

TransitionC3(s, e, result) ==
    \A index \in ChannelEffectIndices(result, "EvictDuplicateChannels") :
        result.effects[index].requesterChannelId = s.channelId

TransitionC4(s, e, result) ==
    ( /\ ValidChannelEvent(e)
      /\ e.kind \in
            {"ChannelJoinReplyReceived", "ChannelErrorObserved",
             "ChannelClosedObserved"}
      /\ ( \/ e.epoch # s.activeJoinEpoch
           \/ e.kind \in
                {"ChannelJoinReplyReceived", "ChannelErrorObserved"}
              /\ s.phase \in {"leaving", "closed"} ) ) =>
        /\ result.disposition = "ignored"
        /\ result.postState = s
        /\ result.effects = <<>>

StateP1(s) ==
    s.phase = "pending" =>
        /\ s.activeRef \in PushRefs
        /\ s.timeoutTimer.armed
        /\ s.timeoutTimer.ref = s.activeRef
        /\ ~s.terminalDelivered

TransitionP1(s, e, result) ==
    PushEffectCount(result, "SendPush") > 0 =>
        /\ result.postState.phase = "pending"
        /\ result.postState.sent
        /\ result.postState.activeRef \in PushRefs
        /\ result.postState.timeoutTimer.armed

StateP2(s) ==
    s.terminalDelivered <=> s.phase = "terminal"

TransitionP2(s, e, result) ==
    /\ PushEffectCount(result, "DeliverPushResult") <= 1
    /\ s.terminalDelivered /\ e.kind # "PushResendRequested" =>
            PushEffectCount(result, "DeliverPushResult") = 0

TransitionIsolation(preState, result) ==
    result.disposition \in {"ignored", "rejected"} =>
        /\ result.postState = preState
        /\ result.effects = <<>>

AllChannelResultsTypeOK(s, StepOperator(_, _)) ==
    \A e \in ChannelEventSet :
        CanChannelStep(s, e) => ChannelResultTypeOK(StepOperator(s, e))

AllPushResultsTypeOK(s, StepOperator(_, _)) ==
    \A e \in PushEventSet :
        CanPushStep(s, e) => PushResultTypeOK(StepOperator(s, e))

AllTransitionC1(s, StepOperator(_, _)) ==
    \A e \in ChannelEventSet :
        CanChannelStep(s, e) => TransitionC1(s, e, StepOperator(s, e))

AllTransitionC2(s, StepOperator(_, _)) ==
    \A e \in ChannelEventSet :
        CanChannelStep(s, e) => TransitionC2(s, e, StepOperator(s, e))

AllTransitionC3(s, StepOperator(_, _)) ==
    \A e \in ChannelEventSet :
        CanChannelStep(s, e) => TransitionC3(s, e, StepOperator(s, e))

AllTransitionC4(s, StepOperator(_, _)) ==
    \A e \in ChannelEventSet :
        CanChannelStep(s, e) => TransitionC4(s, e, StepOperator(s, e))

AllTransitionP1(s, StepOperator(_, _)) ==
    \A e \in PushEventSet :
        CanPushStep(s, e) => TransitionP1(s, e, StepOperator(s, e))

AllTransitionP2(s, StepOperator(_, _)) ==
    \A e \in PushEventSet :
        CanPushStep(s, e) => TransitionP2(s, e, StepOperator(s, e))

AllChannelIsolation(s, StepOperator(_, _)) ==
    \A e \in ChannelEventSet :
        CanChannelStep(s, e) =>
            TransitionIsolation(s, StepOperator(s, e))

AllPushIsolation(s, StepOperator(_, _)) ==
    \A e \in PushEventSet :
        CanPushStep(s, e) =>
            TransitionIsolation(s, StepOperator(s, e))

======================================================================
