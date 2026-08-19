--------------- MODULE M08_SelfRearmRejoinTimer ---------------
\* Historical defect R08: a fired rejoin timer rearms itself even when a
\* connected socket can start a join.

EXTENDS RealtimeChannelPush

MutantChannelStep(s, e) ==
    LET result == CorrectChannelStep(s, e)
    IN IF /\ e.kind = "ChannelRejoinTimerFired"
          /\ s.rejoinTimer.armed
          /\ e.timerId = s.rejoinTimer.id
          /\ s.socketAvailable
       THEN [result EXCEPT
                !.postState.rejoinTimer = s.rejoinTimer]
       ELSE result

===============================================================
