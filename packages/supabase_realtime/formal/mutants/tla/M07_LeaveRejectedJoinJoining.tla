------------- MODULE M07_LeaveRejectedJoinJoining -------------
\* Historical defect R07: a rejected join remains joining and has no
\* rejoin obligation.

EXTENDS RealtimeChannelPush

MutantChannelStep(s, e) ==
    LET result == CorrectChannelStep(s, e)
    IN IF /\ e.kind = "ChannelJoinReplyReceived"
          /\ e.epoch = s.activeJoinEpoch
          /\ e.replyStatus = "error"
          /\ s.phase = "joining"
       THEN [result EXCEPT
                !.postState.phase = "joining",
                !.postState.rejoinTimer = NoEpochTimer,
                !.postState.nextTimerId = s.nextTimerId,
                !.effects = <<EmitChannelErrorEffect("error")>>]
       ELSE result

===============================================================
