----------------- MODULE M05_CarryHeartbeatDebt -----------------
\* Historical defect R05: heartbeat debt survives its connection.

EXTENDS SocketBehavior

MutantStep(s, e) ==
    LET result == CorrectStep(s, e)
    IN IF /\ e.kind = "TransportClosed"
          /\ e.generation = s.activeGeneration
          /\ s.phase = "open"
          /\ s.pendingHeartbeat.active
       THEN [result EXCEPT
                !.postState.pendingHeartbeat = s.pendingHeartbeat]
       ELSE result

=================================================================
