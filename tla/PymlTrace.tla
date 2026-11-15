----------------------------- MODULE PymlTrace -----------------------------
(***************************************************************************)
(* Validation of PymlThreads against the executions of pyml: a trace,     *)
(* written by pyml with PYML_THREADS_TRACE=<file> (one line per step of    *)
(* the model that pyml takes, named after its labels), is accepted if a   *)
(* behavior of the model takes these steps in this order, each one by the  *)
(* thread of the trace, from the label and to the label of the trace (so   *)
(* that the guard of the step holds then: the lock that it takes is free). *)
(*                                                                         *)
(* Between the steps of the trace, the model can take the steps that pyml  *)
(* does not see (Silent): the switches of the GIL by CPython (the eval     *)
(* breaker), the blocking sections of the OCaml code, the registration of  *)
(* a thread in the OCaml runtime (inside caml_c_thread_register), Python   *)
(* code under D, the start and the end of the threads, the calls and       *)
(* returns of the procedures. The collections (OCaml and Python stop-the-  *)
(* world sections) are left out: they only make the other steps wait, so   *)
(* a trace accepted with them is accepted without them.                    *)
(*                                                                         *)
(* The bounds of the model (MaxOps, MaxDepth) are lifted (CanDo, CanNest   *)
(* <- TRUE in the configuration), and the counters ops and depth are left  *)
(* out of the view, so that the silent steps do not make new states.      *)
(*                                                                         *)
(* The trace is accepted if the invariant TraceNotAccepted is violated    *)
(* (TLC prints a behavior that takes all the steps of the trace).          *)
(***************************************************************************)
EXTENDS PymlThreads, TraceData

VARIABLE i  \* the next step of the trace

traceVars == <<vars, i>>

\* A step of thread t, in any of its procedures.
Step(t) ==
  \/ PyCode(t) \/ AllCode(t) \/ OCamlCode(t)
  \/ t \in PyThreads /\ pyth(t)
  \/ t \in OCamlThreads /\ othr(t)

\* The steps that pyml writes in the trace (see trace_step in pyml_stubs.c).
Observed == {
  <<"p_start", "p_unlock">>, <<"p_unlock", "p_run">>,
  <<"py", "py_reg_d">>, <<"py", "py_lockL">>, <<"py_reg_g", "py_lockL">>,
  <<"py_lockL", "py_d">>, <<"py_lockL", "py_waitL">>, <<"py_waitL", "py_g">>,
  <<"py_g", "py_d">>, <<"py_d", "all">>, <<"py_leave", "py_leave_L">>,
  <<"py_leave_L", "py">>,
  <<"all", "all_run_L">>, <<"all_run_L", "all_run">>,
  <<"all_restore", "all_restore_L">>, <<"all_restore_L", "all_restore_g">>,
  <<"all_restore_g", "all_restore_d">>, <<"all_restore_d", "all">>,
  <<"all", "all_call_unlock">>, <<"all_call_unlock", "all_call">>,
  <<"all_call_back", "all_call_d">>, <<"all_call_back", "all_call_L">>,
  <<"all_call_L", "all_call_g">>, <<"all_call_g", "all_call_d">>,
  <<"all_call_d", "all">>,
  <<"oc", "oc_rp_L1">>, <<"oc_rp_L1", "oc_rp_g1">>, <<"oc_rp_g1", "oc_rp_d1">>,
  <<"oc_rp_d1", "all">>, <<"oc_rp_back1", "oc_rp_unlock1">>,
  <<"oc_rp_unlock1", "oc">>,
  <<"oc", "oc_rp_L2">>, <<"oc_rp_L2", "oc_rp_g2">>, <<"oc_rp_g2", "oc_rp_d2">>,
  <<"oc_rp_d2", "all">>, <<"oc_rp_back2", "oc_rp_unlock2">>,
  <<"oc_rp_unlock2", "oc">>
}

\* The collections, left out.
Collections == {"all_gc", "oc_gc", "py_pstw", "all_pstw"}

TraceInit == Init /\ i = 1

\* The next step of the trace.
ObservedStep ==
  /\ i <= Len(TraceSeq)
  /\ LET e == TraceSeq[i] IN
       /\ pc[e.t] = e.from
       /\ Step(e.t)
       /\ pc'[e.t] = e.to
  /\ i' = i + 1

\* A step that pyml does not see, by a thread that has started in the trace
\* (the trace has reached its first step: the threads of the model exist
\* from the start, but the threads of the program start later).
SilentStepOf(t) ==
  /\ TFirst[t] <= i
  /\ Step(t)
  /\ <<pc[t], pc'[t]>> \notin Observed
  /\ pc'[t] \notin Collections
  /\ UNCHANGED i

\* The silent steps that start a detour by releasing a lock: the switch of
\* the GIL at the eval breaker, Python code under D that releases G, a tick
\* of the systhreads in STATE_ALL (D yielded), and a blocking section of the
\* OCaml code (or a tick: they release D the same way).
DetourStarts == {<<"py", "py_reattach">>, <<"all", "all_pyd">>,
                 <<"all", "all_yield">>, <<"oc", "oc_bl_d">>}

\* The labels where the detours end, taking the lock again (a thread that
\* holds G and yielded D at a tick takes D again before Python code under D
\* releases G).
DetourEnds == {"py_reattach", "all_pyd", "all_yield", "oc_bl_d"}

\* The silent steps of the thread of the next step of the trace, except the
\* starts of detours: the calls and returns of the procedures, the ends of
\* the detours (which take the lock again), the start of the thread.
OwnStep ==
  /\ i <= Len(TraceSeq)
  /\ LET t == TraceSeq[i].t IN
       /\ SilentStepOf(t)
       /\ <<pc[t], pc'[t]>> \notin DetourStarts

\* The silent steps of the other threads that release a lock that the
\* next step of the trace may wait for (the starts of detours; L is only
\* released by the steps of the trace), or that take no lock and release
\* none (to reach the start of a detour: a thread that has just entered
\* run_ocaml calls OCamlCode before it can enter a blocking section), or
\* that end a detour.
OtherRelease ==
  /\ i <= Len(TraceSeq)
  /\ \E t \in Threads \ {TraceSeq[i].t} :
       /\ SilentStepOf(t)
       /\ \/ <<pc[t], pc'[t]>> \in DetourStarts
          \/ pc[t] \in DetourEnds
          \/ UNCHANGED <<L, attached, D>>

\* The next step of the trace is taken as soon as it can be; otherwise, the
\* silent steps of its thread (to reach the label of the step, with the
\* locks of its detours taken again), and otherwise the releases of locks
\* by the other threads (which explain why it waits). Without these
\* priorities, the silent steps of all the threads interleave, and the
\* search explodes with the number of threads. They only remove behaviors:
\* a trace accepted this way is a behavior of the model; a trace rejected
\* this way could still be one (the rejections are checked by hand).
TraceNext ==
  IF ENABLED ObservedStep THEN ObservedStep
  ELSE IF ENABLED OwnStep THEN OwnStep
  ELSE OtherRelease

TraceSpec == TraceInit /\ [][TraceNext]_traceVars

TraceView == <<L, attached, D, st, registered, ostw, pstw, slot, pc, stack,
               saved, i>>

\* Violated when the whole trace is taken: the trace is accepted.
TraceNotAccepted == i <= Len(TraceSeq)

\* The bounds are lifted (CanDo <- Unbounded, CanNest <- Unbounded).
Unbounded(t) == TRUE

\* The longest prefix of the trace taken, printed when it grows (for the
\* traces that are not accepted).
ASSUME TLCSet(1, 1)
Progress == i > TLCGet(1) => TLCSet(1, i) /\ PrintT(<<"prefix", i - 1>>)
=============================================================================
