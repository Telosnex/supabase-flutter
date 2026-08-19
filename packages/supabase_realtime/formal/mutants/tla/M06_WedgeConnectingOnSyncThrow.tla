------------- MODULE M06_WedgeConnectingOnSyncThrow -------------
\* Historical defect R06: synchronous construction failure leaves
\* connecting without an owned transport.

EXTENDS SocketBehavior

MutantStep(s, e) ==
    LET result == CorrectStep(s, e)
    IN IF /\ e.kind = "TransportOpenFailed"
          /\ e.failureKind = "sync"
          /\ e.generation = s.activeGeneration
          /\ s.phase = "connecting"
          /\ s.intent = "up"
       THEN [result EXCEPT
                !.postState.phase = "connecting"]
       ELSE result

=================================================================
