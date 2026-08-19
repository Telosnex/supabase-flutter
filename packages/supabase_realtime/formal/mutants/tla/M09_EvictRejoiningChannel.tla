--------------- MODULE M09_EvictRejoiningChannel ---------------
\* Historical defect R09: duplicate eviction does not protect the channel
\* that requested the rejoin.

EXTENDS RealtimeChannelPush

MutantChannelStep(s, e) ==
    LET result == CorrectChannelStep(s, e)
    IN IF result.action \in {"startChannelJoin", "startChannelRejoin"}
       THEN [result EXCEPT
                !.effects =
                    [index \in 1..Len(@) |->
                        IF @[index].kind = "EvictDuplicateChannels"
                        THEN [@[index] EXCEPT !.requesterChannelId = 0]
                        ELSE @[index]]]
       ELSE result

================================================================
