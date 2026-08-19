-------------------------- MODULE PushOracle --------------------------
EXTENDS ChannelPushTransitions, ReachablePushStates

VARIABLES preState, event, result
vars == <<preState, event, result>>

EligiblePushStates ==
    {state \in ReachablePushStates :
        \A candidate \in PushEventSet : CanPushStep(state, candidate)}

Init ==
    /\ preState \in EligiblePushStates
    /\ event \in PushEventSet
    /\ result = CorrectPushStep(preState, event)

Next == UNCHANGED vars
Spec == Init /\ [][Next]_vars

OracleTypeOK ==
    /\ PushStateTypeOK(preState)
    /\ PushEventTypeOK(event)
    /\ PushResultTypeOK(result)
    /\ result = CorrectPushStep(preState, event)

=======================================================================
