------------------------ MODULE ChannelOracle ------------------------
EXTENDS ChannelPushTransitions, ReachableChannelStates

VARIABLES preState, event, result
vars == <<preState, event, result>>

EligibleChannelStates ==
    {state \in ReachableChannelStates :
        \A candidate \in ChannelEventSet : CanChannelStep(state, candidate)}

Init ==
    /\ preState \in EligibleChannelStates
    /\ event \in ChannelEventSet
    /\ result = CorrectChannelStep(preState, event)

Next == UNCHANGED vars
Spec == Init /\ [][Next]_vars

OracleTypeOK ==
    /\ ChannelStateTypeOK(preState)
    /\ ChannelEventTypeOK(event)
    /\ ChannelResultTypeOK(result)
    /\ result = CorrectChannelStep(preState, event)

=======================================================================
