-------------- MODULE M01_KeepPushTimeoutOnResend --------------
\* Historical defect R01: resend leaves the stale timer, so the new push
\* is sent without a fresh ref/timer ownership pair.

EXTENDS RealtimeChannelPush

MutantPushStep(s, e) ==
    LET result == CorrectPushStep(s, e)
    IN IF /\ e.kind = "PushResendRequested"
          /\ s.phase = "pending"
       THEN [result EXCEPT
                !.postState.activeRef = 0,
                !.postState.timeoutTimer = s.timeoutTimer,
                !.postState.nextRef = s.nextRef,
                !.postState.nextTimerId = s.nextTimerId,
                !.effects = <<SendPushEffect(0)>>]
       ELSE result

================================================================
