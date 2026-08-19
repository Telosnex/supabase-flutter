------------------------ MODULE SocketBehavior ------------------------
\* Reachability and named checks for a supplied pure Step operator.

EXTENDS SocketTransitions

CONSTANT StepOperator(_,_)

VARIABLES
    state,
    scopeExhausted

vars == <<state, scopeExhausted>>

Init ==
    /\ state = InitialState
    /\ scopeExhausted = FALSE

AppliedStateChange ==
    /\ ~scopeExhausted
    /\ \E event \in EventSet :
        /\ CanStep(state, event)
        /\ LET result == StepOperator(state, event)
           IN /\ result.disposition = "applied"
              /\ result.postState # state
              /\ state' = result.postState
              /\ UNCHANGED scopeExhausted

RecordScopeExhaustion ==
    /\ ~scopeExhausted
    /\ \E event \in EventSet : ~CanStep(state, event)
    /\ scopeExhausted' = TRUE
    /\ UNCHANGED state

Next == AppliedStateChange \/ RecordScopeExhaustion

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ StateTypeOK(state)
    /\ scopeExhausted \in BOOLEAN
    /\ AllResultsTypeOK(state, StepOperator)

S1_NoWorkAgainstDownIntent ==
    /\ state.intent = "down" => ~state.reconnectTimer.armed
    /\ AllTransitionS1(state, StepOperator)

S2_FailureSchedulesRecovery == AllTransitionS2(state, StepOperator)

S3_PhaseOwnsTransport == StateS3(state)

S4_HeartbeatOwnedByGeneration == StateS4(state)

S5_BackoffOrdinal == AllTransitionS5(state, StepOperator)

S6_HeartbeatRefreshesTokenSource == AllTransitionS6(state, StepOperator)

T1_OneTimerPerPurpose == StateT1(state)

T2_StaleEventIsolation == AllTransitionT2(state, StepOperator)

T3_FreshOpenHasNoDebt == AllTransitionT3(state, StepOperator)

T4_OneTransportEffect == AllTransitionT4(state, StepOperator)

T5_DownQuiescence == StateT5(state)

T6_CloseMetadataConsistent == StateT6(state)

=======================================================================
