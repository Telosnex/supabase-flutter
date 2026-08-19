------------------------- MODULE SocketOracle -------------------------
\* TLC evaluates the pure Step operator over every eligible R_B x E_B pair.
\* ReachableStates.tla is generated under .dart_tool from TLC's safety dump.

EXTENDS SocketTransitions, ReachableStates

VARIABLES
    preState,
    event,
    result

vars == <<preState, event, result>>

EligibleReachableStates ==
    {candidate \in ReachableStates : OracleEligible(candidate)}

Init ==
    /\ preState \in EligibleReachableStates
    /\ event \in EventSet
    /\ result = CorrectStep(preState, event)

Next == UNCHANGED vars

Spec == Init /\ [][Next]_vars

OracleTypeOK ==
    /\ StateTypeOK(preState)
    /\ EventTypeOK(event)
    /\ ResultTypeOK(result)
    /\ result = CorrectStep(preState, event)

=======================================================================
