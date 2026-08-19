------------- MODULE M12_ResetRetryDuringRecovery -------------
\* Historical defect R12: internal recovery resets the backoff count.

EXTENDS SocketBehavior

MutantStep(s, e) ==
    LET result == CorrectStep(s, e)
    IN IF result.action = "startReconnectAttempt"
       THEN [result EXCEPT !.postState.retryCount = 0]
       ELSE result

===============================================================
