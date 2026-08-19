------------------ MODULE LifecycleTraceValidation ------------------
\* Validates concrete socket/channel/push traces loaded with TLC JSON replay.

EXTENDS SocketTransitions, TraceEntries

CONSTANTS
    ExpectedModelHash,
    MaxChannelId,
    MaxJoinEpoch,
    MaxPushRef,
    MaxChannelPushTimerId

CP == INSTANCE ChannelPushTransitions
        WITH MaxTimerId <- MaxChannelPushTimerId

VARIABLE entry

EntryResult(value) ==
    [ disposition |-> value.disposition,
      action      |-> value.action,
      postState   |-> value.postState,
      effects     |-> value.effects ]

EntryStepOK(value) ==
    CASE value.machine = "socket" ->
            /\ StateTypeOK(value.preState)
            /\ EventTypeOK(value.event)
            /\ ResultTypeOK(EntryResult(value))
            /\ EntryResult(value) = CorrectStep(value.preState, value.event)
      [] value.machine = "channel" ->
            /\ CP!ChannelStateTypeOK(value.preState)
            /\ CP!ChannelEventTypeOK(value.event)
            /\ CP!ChannelResultTypeOK(EntryResult(value))
            /\ EntryResult(value) =
                    CP!CorrectChannelStep(value.preState, value.event)
      [] value.machine = "push" ->
            /\ CP!PushStateTypeOK(value.preState)
            /\ CP!PushEventTypeOK(value.event)
            /\ CP!PushResultTypeOK(EntryResult(value))
            /\ EntryResult(value) =
                    CP!CorrectPushStep(value.preState, value.event)
      [] OTHER -> FALSE

EntryInitialOK(value) ==
    CASE value.machine = "socket" -> value.preState = InitialState
      [] value.machine = "channel" ->
            value.preState =
                CP!InitialChannelState(value.preState.channelId)
      [] value.machine = "push" -> value.preState = CP!InitialPushState
      [] OTHER -> FALSE

EntryOK(value) ==
    /\ value.schemaHash = ManifestSha256
    /\ value.modelHash = ExpectedModelHash
    /\ value.machine \in {"socket", "channel", "push"}
    /\ value.instance \in STRING
    /\ value.sequence \in Nat \ {0}
    /\ EntryStepOK(value)

Init ==
    /\ entry \in TraceEntries
    /\ entry.sequence = 1
    /\ EntryInitialOK(entry)
    /\ EntryOK(entry)

Next ==
    /\ entry' \in TraceEntries
    /\ entry'.machine = entry.machine
    /\ entry'.instance = entry.instance
    /\ entry'.sequence = entry.sequence + 1
    /\ entry'.preState = entry.postState
    /\ EntryOK(entry')

Spec == Init /\ [][Next]_entry

TraceEntryOK == EntryOK(entry)

======================================================================
