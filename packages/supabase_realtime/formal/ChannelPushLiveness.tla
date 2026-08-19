------------------- MODULE ChannelPushLiveness -------------------
\* Unbounded-identity liveness abstraction for channel joins and pushes.

EXTENDS Naturals

VARIABLES
    desiredChannelIntent,
    channelIntent,
    channelPhase,
    rejoinArmed,
    networkHealed,
    pushPhase

vars ==
    <<desiredChannelIntent, channelIntent, channelPhase, rejoinArmed,
      networkHealed, pushPhase>>

Init ==
    /\ desiredChannelIntent = "left"
    /\ channelIntent = "left"
    /\ channelPhase = "closed"
    /\ rejoinArmed = FALSE
    /\ networkHealed = FALSE
    /\ pushPhase = "idle"

UserSubscribes ==
    /\ desiredChannelIntent = "left"
    /\ desiredChannelIntent' = "joined"
    /\ UNCHANGED <<channelIntent, channelPhase, rejoinArmed,
                    networkHealed, pushPhase>>

UserUnsubscribes ==
    /\ desiredChannelIntent = "joined"
    /\ desiredChannelIntent' = "left"
    /\ UNCHANGED <<channelIntent, channelPhase, rejoinArmed,
                    networkHealed, pushPhase>>

NetworkHeals ==
    /\ ~networkHealed
    /\ networkHealed' = TRUE
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, channelPhase,
                    rejoinArmed, pushPhase>>

NetworkBreaks ==
    /\ networkHealed
    /\ networkHealed' = FALSE
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, channelPhase,
                    rejoinArmed, pushPhase>>

ProcessSubscribe ==
    /\ desiredChannelIntent = "joined"
    /\ channelIntent = "left"
    /\ channelIntent' = "joined"
    /\ channelPhase' = "joining"
    /\ rejoinArmed' = FALSE
    /\ UNCHANGED <<desiredChannelIntent, networkHealed, pushPhase>>

ProcessUnsubscribe ==
    /\ desiredChannelIntent = "left"
    /\ channelIntent = "joined"
    /\ channelIntent' = "left"
    /\ channelPhase' = "closed"
    /\ rejoinArmed' = FALSE
    /\ pushPhase' = IF pushPhase = "pending" THEN "terminal" ELSE pushPhase
    /\ UNCHANGED <<desiredChannelIntent, networkHealed>>

ProcessChannelIntent == ProcessSubscribe \/ ProcessUnsubscribe

JoinFails ==
    /\ ~networkHealed
    /\ channelIntent = "joined"
    /\ channelPhase = "joining"
    /\ channelPhase' = "errored"
    /\ rejoinArmed' = TRUE
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, networkHealed,
                    pushPhase>>

CurrentRejoinTimerFires ==
    /\ rejoinArmed
    /\ channelIntent = "joined"
    /\ channelPhase = "errored"
    /\ rejoinArmed' = FALSE
    /\ channelPhase' = "joining"
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, networkHealed,
                    pushPhase>>

HealedJoinSucceeds ==
    /\ networkHealed
    /\ channelIntent = "joined"
    /\ channelPhase = "joining"
    /\ channelPhase' = "joined"
    /\ rejoinArmed' = FALSE
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, networkHealed,
                    pushPhase>>

UserSendsPush ==
    /\ channelPhase = "joined"
    /\ pushPhase = "idle"
    /\ pushPhase' = "pending"
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, channelPhase,
                    rejoinArmed, networkHealed>>

PushOutcomeArrives ==
    /\ pushPhase = "pending"
    /\ pushPhase' = "terminal"
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, channelPhase,
                    rejoinArmed, networkHealed>>

UserStartsAnotherPush ==
    /\ pushPhase = "terminal"
    /\ pushPhase' = "idle"
    /\ UNCHANGED <<desiredChannelIntent, channelIntent, channelPhase,
                    rejoinArmed, networkHealed>>

Next ==
    \/ UserSubscribes
    \/ UserUnsubscribes
    \/ NetworkHeals
    \/ NetworkBreaks
    \/ ProcessChannelIntent
    \/ JoinFails
    \/ CurrentRejoinTimerFires
    \/ HealedJoinSucceeds
    \/ UserSendsPush
    \/ PushOutcomeArrives
    \/ UserStartsAnotherPush

BaseSpec == Init /\ [][Next]_vars

AssumptionWF_ChannelEventLoop == WF_vars(ProcessChannelIntent)
AssumptionWF_CurrentRejoinTimer == WF_vars(CurrentRejoinTimerFires)
AssumptionWF_HealedJoin == WF_vars(HealedJoinSucceeds)
AssumptionWF_PushOutcome == WF_vars(PushOutcomeArrives)

LivenessSpec ==
    /\ BaseSpec
    /\ AssumptionWF_ChannelEventLoop
    /\ AssumptionWF_CurrentRejoinTimer
    /\ AssumptionWF_HealedJoin
    /\ AssumptionWF_PushOutcome

TypeOK ==
    /\ desiredChannelIntent \in {"joined", "left"}
    /\ channelIntent \in {"joined", "left"}
    /\ channelPhase \in {"closed", "joining", "joined", "errored"}
    /\ rejoinArmed \in BOOLEAN
    /\ networkHealed \in BOOLEAN
    /\ pushPhase \in {"idle", "pending", "terminal"}
    /\ rejoinArmed =>
        (channelIntent = "joined" /\ channelPhase = "errored")

L1_ChannelEventuallyJoined ==
    (<>[](desiredChannelIntent = "joined" /\ networkHealed)) =>
        <>[](channelPhase = "joined")

L2_PushEventuallyTerminal ==
    [](pushPhase = "pending" => <> (pushPhase = "terminal"))

===================================================================
