---------------- MODULE M02_BypassTokenProvider ----------------
\* Historical defect R02: a heartbeat bypasses customAccessToken.

EXTENDS SocketBehavior

MutantStep(s, e) ==
    LET result == CorrectStep(s, e)
    IN IF result.action = "sendHeartbeat"
       THEN [result EXCEPT
                !.effects = SubSeq(@, 1, Len(@) - 1)]
       ELSE result

================================================================
