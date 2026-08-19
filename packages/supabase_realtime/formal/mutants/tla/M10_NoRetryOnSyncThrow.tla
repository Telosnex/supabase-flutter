---------------- MODULE M10_NoRetryOnSyncThrow ----------------
\* Historical defect R10: synchronous construction failure emits an
\* error but does not arm reconnect.

EXTENDS SocketBehavior

MutantStep(s, e) ==
    LET result == CorrectStep(s, e)
    IN IF /\ e.kind = "TransportOpenFailed"
          /\ e.failureKind = "sync"
          /\ e.generation = s.activeGeneration
          /\ s.phase = "connecting"
          /\ s.intent = "up"
       THEN [result EXCEPT
                !.postState.reconnectTimer = NoReconnectTimer,
                !.postState.nextTimerId = s.nextTimerId,
                !.effects = SubSeq(@, 1, Len(@) - 1)]
       ELSE result

==============================================================
