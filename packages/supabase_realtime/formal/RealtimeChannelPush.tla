--------------------- MODULE RealtimeChannelPush ---------------------
\* Reachability and safety checks for channel and push kernels.

EXTENDS ChannelPushTransitions

CONSTANTS
    ChannelStepOperator(_,_),
    PushStepOperator(_,_)

VARIABLES
    channel,
    push,
    scopeExhausted

vars == <<channel, push, scopeExhausted>>

Init ==
    /\ channel \in {InitialChannelState(channelId) : channelId \in ChannelIds}
    /\ push = InitialPushState
    /\ scopeExhausted = FALSE

AppliedChannelChange ==
    /\ ~scopeExhausted
    /\ \E event \in ChannelEventSet :
        /\ CanChannelStep(channel, event)
        /\ LET result == ChannelStepOperator(channel, event)
           IN /\ result.disposition = "applied"
              /\ result.postState # channel
              /\ channel' = result.postState
              /\ UNCHANGED <<push, scopeExhausted>>

AppliedPushChange ==
    /\ ~scopeExhausted
    /\ \E event \in PushEventSet :
        /\ CanPushStep(push, event)
        /\ LET result == PushStepOperator(push, event)
           IN /\ result.disposition = "applied"
              /\ result.postState # push
              /\ push' = result.postState
              /\ UNCHANGED <<channel, scopeExhausted>>

RecordScopeExhaustion ==
    /\ ~scopeExhausted
    /\ ( \/ \E event \in ChannelEventSet :
                ~CanChannelStep(channel, event)
         \/ \E event \in PushEventSet : ~CanPushStep(push, event) )
    /\ scopeExhausted' = TRUE
    /\ UNCHANGED <<channel, push>>

Next == AppliedChannelChange \/ AppliedPushChange \/ RecordScopeExhaustion

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ ChannelStateTypeOK(channel)
    /\ PushStateTypeOK(push)
    /\ scopeExhausted \in BOOLEAN
    /\ AllChannelResultsTypeOK(channel, ChannelStepOperator)
    /\ AllPushResultsTypeOK(push, PushStepOperator)

C1_JoinFailureSchedulesRejoin ==
    /\ StateC1(channel)
    /\ AllTransitionC1(channel, ChannelStepOperator)

C2_RejoinTimerOwned ==
    /\ StateC2(channel)
    /\ AllTransitionC2(channel, ChannelStepOperator)

C3_DuplicateEvictionExcludesRequester ==
    AllTransitionC3(channel, ChannelStepOperator)

C4_StaleJoinIsolation ==
    AllTransitionC4(channel, ChannelStepOperator)

P1_SentPushOwnsRefAndTimer ==
    /\ StateP1(push)
    /\ AllTransitionP1(push, PushStepOperator)

P2_AtMostOneTerminalResult ==
    /\ StateP2(push)
    /\ AllTransitionP2(push, PushStepOperator)

ChannelStaleIsolation ==
    AllChannelIsolation(channel, ChannelStepOperator)

PushStaleIsolation ==
    AllPushIsolation(push, PushStepOperator)

=======================================================================
