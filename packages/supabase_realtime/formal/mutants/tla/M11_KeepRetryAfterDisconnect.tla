------------- MODULE M11_KeepRetryAfterDisconnect -------------
\* Historical defect R11: explicit disconnect leaves reconnect armed.

EXTENDS SocketBehavior

MutantStep(s, e) ==
    LET result == CorrectStep(s, e)
    IN IF /\ e.kind = "DisconnectRequested"
          /\ s.reconnectTimer.armed
       THEN [result EXCEPT
                !.postState.reconnectTimer = s.reconnectTimer,
                !.effects = <<>>]
       ELSE result

===============================================================
