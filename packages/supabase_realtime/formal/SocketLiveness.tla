------------------------ MODULE SocketLiveness ------------------------
\* Unbounded-identity liveness abstraction. Safety and identity uniqueness are
\* checked by RealtimeSocket; this module checks convergence assumptions.

EXTENDS Naturals

VARIABLES
    desiredIntent,
    intent,
    phase,
    reconnectArmed,
    closePending,
    networkHealed

vars ==
    <<desiredIntent, intent, phase, reconnectArmed, closePending,
      networkHealed>>

Init ==
    /\ desiredIntent = "down"
    /\ intent = "down"
    /\ phase = "idle"
    /\ reconnectArmed = FALSE
    /\ closePending = FALSE
    /\ networkHealed = FALSE

UserRequestsUp ==
    /\ desiredIntent = "down"
    /\ desiredIntent' = "up"
    /\ UNCHANGED <<intent, phase, reconnectArmed, closePending,
                    networkHealed>>

UserRequestsDown ==
    /\ desiredIntent = "up"
    /\ desiredIntent' = "down"
    /\ UNCHANGED <<intent, phase, reconnectArmed, closePending,
                    networkHealed>>

NetworkHeals ==
    /\ ~networkHealed
    /\ networkHealed' = TRUE
    /\ UNCHANGED <<desiredIntent, intent, phase, reconnectArmed,
                    closePending>>

NetworkBreaks ==
    /\ networkHealed
    /\ networkHealed' = FALSE
    /\ UNCHANGED <<desiredIntent, intent, phase, reconnectArmed,
                    closePending>>

ProcessUpIntent ==
    /\ desiredIntent = "up"
    /\ intent = "down"
    /\ intent' = "up"
    /\ reconnectArmed' = FALSE
    /\ IF phase = "idle"
       THEN /\ phase' = "connecting"
            /\ closePending' = FALSE
       ELSE /\ phase' = phase
            /\ closePending' = closePending
    /\ UNCHANGED <<desiredIntent, networkHealed>>

ProcessDownIntent ==
    /\ desiredIntent = "down"
    /\ intent = "up"
    /\ intent' = "down"
    /\ reconnectArmed' = FALSE
    /\ IF phase \in {"connecting", "open"}
       THEN /\ phase' = "closing"
            /\ closePending' = TRUE
       ELSE /\ phase' = phase
            /\ closePending' = closePending
    /\ UNCHANGED <<desiredIntent, networkHealed>>

ProcessRequestedIntent == ProcessUpIntent \/ ProcessDownIntent

CurrentTimerFires ==
    /\ reconnectArmed
    /\ intent = "up"
    /\ phase = "idle"
    /\ reconnectArmed' = FALSE
    /\ phase' = "connecting"
    /\ UNCHANGED <<desiredIntent, intent, closePending, networkHealed>>

CloseOutcomeArrives ==
    /\ closePending
    /\ phase = "closing"
    /\ closePending' = FALSE
    /\ IF intent = "down"
       THEN /\ phase' = "idle"
            /\ reconnectArmed' = FALSE
       ELSE /\ phase' = "idle"
            /\ reconnectArmed' = TRUE
    /\ UNCHANGED <<desiredIntent, intent, networkHealed>>

HealedOpenSucceeds ==
    /\ networkHealed
    /\ intent = "up"
    /\ phase = "connecting"
    /\ phase' = "open"
    /\ UNCHANGED <<desiredIntent, intent, reconnectArmed, closePending,
                    networkHealed>>

TransportFails ==
    /\ ~networkHealed
    /\ intent = "up"
    /\ phase \in {"connecting", "open"}
    /\ IF phase = "connecting"
       THEN /\ phase' = "idle"
            /\ reconnectArmed' = TRUE
            /\ closePending' = FALSE
       ELSE /\ phase' = "closing"
            /\ reconnectArmed' = FALSE
            /\ closePending' = TRUE
    /\ UNCHANGED <<desiredIntent, intent, networkHealed>>

Next ==
    \/ UserRequestsUp
    \/ UserRequestsDown
    \/ NetworkHeals
    \/ NetworkBreaks
    \/ ProcessRequestedIntent
    \/ CurrentTimerFires
    \/ CloseOutcomeArrives
    \/ HealedOpenSucceeds
    \/ TransportFails

BaseSpec == Init /\ [][Next]_vars

\* TLA+ reserves the WF_ prefix, so the reviewed WF_* assumption names are
\* represented by operators whose identifiers end in those exact labels.
AssumptionWF_EventLoop == WF_vars(ProcessRequestedIntent)
AssumptionWF_CurrentTimer == WF_vars(CurrentTimerFires)
AssumptionWF_CloseOutcome == WF_vars(CloseOutcomeArrives)
AssumptionWF_HealedOpen == WF_vars(HealedOpenSucceeds)

LivenessSpec ==
    /\ BaseSpec
    /\ AssumptionWF_EventLoop
    /\ AssumptionWF_CurrentTimer
    /\ AssumptionWF_CloseOutcome
    /\ AssumptionWF_HealedOpen

TypeOK ==
    /\ desiredIntent \in {"up", "down"}
    /\ intent \in {"up", "down"}
    /\ phase \in {"idle", "connecting", "open", "closing"}
    /\ reconnectArmed \in BOOLEAN
    /\ closePending \in BOOLEAN
    /\ networkHealed \in BOOLEAN
    /\ (closePending <=> phase = "closing")
    /\ reconnectArmed => (intent = "up" /\ phase = "idle")

Quiescent ==
    /\ intent = "down"
    /\ phase = "idle"
    /\ ~reconnectArmed
    /\ ~closePending

L3_DownEventuallyQuiescent ==
    (<>[](desiredIntent = "down")) => <>[]Quiescent

L4_UpEventuallyOpen ==
    (<>[](desiredIntent = "up" /\ networkHealed)) => <>[](phase = "open")

=======================================================================
