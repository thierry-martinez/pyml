---------------------------- MODULE PymlThreads ----------------------------
(***************************************************************************)
(* The locks of Py.Thread (pyml, branch threads-fix-deadlock, commit     *)
(* afca177, merge request tmartine/pyml!4: pyml_stubs.c, "Threads"), as    *)
(* ocip uses them. STATE_OCAML (Py.Thread.run_ocaml) holds D only.         *)
(*                                                                         *)
(* Locks:                                                                  *)
(*   L        the world lock of pyml (ocip's state)                        *)
(*   attached the threads that hold the GIL (G), or, with free-threaded    *)
(*            Python, the threads whose thread state is attached           *)
(*   D[d]     the lock of the OCaml domain d (the master lock of its       *)
(*            systhreads)                                                  *)
(* and the stop-the-world sections of OCaml (ostw: the minor collections,  *)
(* which wait for every domain whose lock is held to reach a safepoint)    *)
(* and of free-threaded Python (pstw: its collections, which wait for      *)
(* every attached thread to detach).                                       *)
(*                                                                         *)
(* Each label is an atomic step; every lock acquisition starts a step.     *)
(* The procedures follow the code of pyml:                                 *)
(*   PyCode    Python code (a Python thread, or a function called with     *)
(*             Py.Thread.call), which calls OCaml through                  *)
(*             pyml_threads_enter_from_python / leave_to_python            *)
(*   AllCode   STATE_ALL: the code of ocip (conversions, lookups), which   *)
(*             applies OCaml functions in Py.Thread.run_ocaml              *)
(*             (release/restore) and calls Python with Py.Thread.call      *)
(*   OCamlCode the OCaml code in run_ocaml (STATE_OCAML) or of OCaml       *)
(*             threads and domains (STATE_UNKNOWN): blocking sections,     *)
(*             Py.Thread.run_python (acquire/unacquire, which also wraps   *)
(*             Py.Thread.call), minor collections.                         *)
(*                                                                         *)
(* PythonUnderD enables the Python code that runs while D is held and      *)
(* releases G meanwhile (conversions, __del__, the comparison and the hash *)
(* of Python objects). Such code runs in STATE_ALL only: the Python API   *)
(* raises Failure in run_ocaml, and run_ocaml does not release the locks   *)
(* in comparisons and hashes.                                              *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
  PyThreads,     \* Python threads; P1 is the one that loaded ocip
  OCamlThreads,  \* OCaml threads and domains
  P1,
  Domains,       \* the OCaml domains; Python threads are in domain 1
  ODom(_),       \* the domain of an OCaml thread
  FreeThreaded,  \* free-threaded Python (no GIL, Python stop-the-world)
  PythonUnderD,  \* Python code under D may release G (see above)
  PerThreadSlot, \* run_ocaml keeps the detached thread state in one slot
                 \* per thread (pyml before 8fe89a7), not per call
  MaxOps,        \* operations per thread (bounds the state space)
  MaxDepth,      \* nesting of calls between OCaml and Python
  None

Threads == PyThreads \cup OCamlThreads

Dom(t) == IF t \in PyThreads THEN 1 ELSE ODom(t)

(* --algorithm PymlThreads {
variables
  L = P1;
  attached = {P1};
  D = [d \in Domains |-> IF d = 1 THEN P1 ELSE None];
  st = [t \in Threads |-> IF t = P1 THEN "ALL" ELSE "UNKNOWN"];
  registered = [t \in Threads |-> t = P1 \/ t \in OCamlThreads];
  ostw = None;
  pstw = None;
  ops = [t \in Threads |-> MaxOps];
  depth = [t \in Threads |-> 0];
  \* The slot of the detached thread state of each thread (PerThreadSlot).
  slot = [t \in Threads |-> None];

define {
  CanAttach(t) == IF FreeThreaded THEN pstw \in {None, t} ELSE attached = {}
  HoldsD(t) == D[Dom(t)] = t
  CanDo(t) == ops[t] > 0
  CanNest(t) == ops[t] > 0 /\ depth[t] < MaxDepth
  \* A stop-the-world of t waits for the holder of D[d] to reach a safepoint
  \* (the OCaml code of the labels "all" and "oc"); a domain whose lock is
  \* free is handled by its backup thread.
  SafeFor(d, t) ==
    IF D[d] = None \/ D[d] = t THEN TRUE ELSE pc[D[d]] \in {"all", "oc"}
}

macro detach() { attached := attached \ {self}; }
\* The order L, G, D is checked when a lock is taken (not from the names of
\* the labels): G is never taken while holding D, except by the holder of
\* L (the Python code under D in STATE_ALL, PythonUnderD), and L never
\* while holding G or D.
macro attach() {
  await CanAttach(self);
  assert L = self \/ ~HoldsD(self);
  attached := attached \cup {self};
}
macro takeL() {
  await L = None;
  assert self \notin attached /\ ~HoldsD(self);
  L := self;
}
macro takeD() { await D[Dom(self)] = None; D[Dom(self)] := self; }
macro dropD() { D[Dom(self)] := None; }
macro spend() { ops[self] := ops[self] - 1; }

\* Python code, holding G (not L, not D).
procedure PyCode() {
py:
  either {
    \* Eval breaker: switch of the GIL, or detach for a stop-the-world.
    await CanDo(self);
    spend(); detach();
    goto py_reattach;
  } or {
    \* A collection of free-threaded Python.
    await FreeThreaded /\ CanDo(self) /\ pstw = None;
    spend(); pstw := self;
    goto py_pstw;
  } or {
    \* Python calls OCaml (pycall_callback).
    await CanNest(self);
    spend(); depth[self] := depth[self] + 1;
    if (registered[self]) {
      goto py_lockL;
    } else {
      \* caml_c_thread_register takes D: G is released before.
      detach();
      goto py_reg_d;
    };
  } or {
    return;
  };
py_reattach:
  attach(); goto py;
py_pstw:
  await attached = {self}; pstw := None; goto py;
py_reg_d:
  takeD();
py_reg_undo:
  dropD(); registered[self] := TRUE;
py_reg_g:
  attach();
py_lockL:
  \* lock_world_holding_gil: trylock, else G is released while waiting.
  if (L = None) { L := self; goto py_d; } else { detach(); };
py_waitL:
  takeL();
py_g:
  attach();
py_d:
  \* caml_leave_blocking_section: D.
  takeD(); st[self] := "ALL";
  call AllCode();
py_leave:
  \* pyml_threads_leave_to_python: caml_enter_blocking_section, then L
  \* (each release is a step: another thread can take D before L is
  \* released).
  dropD(); st[self] := "PYTHON";
  depth[self] := depth[self] - 1;
py_leave_L:
  L := None;
  goto py;
}

\* STATE_ALL: L, G and D are held (the code of ocip).
\* saved: the thread state detached by the run_ocaml of this call (the
\* result of Py.Thread.release, kept by run_ocaml until restore): local to
\* the call, as the stack of the OCaml code holds it. The thread states are
\* named after their threads.
procedure AllCode()
  variables saved = None;
{
all:
  await ostw \in {None, self};
  either {
    \* A minor collection (stop-the-world).
    await CanDo(self) /\ ostw = None;
    spend(); ostw := self;
    goto all_gc;
  } or {
    \* Py.Thread.run_ocaml: release (PyEval_SaveThread, then L; D kept).
    await CanNest(self);
    spend(); depth[self] := depth[self] + 1;
    detach(); st[self] := "OCAML";
    if (PerThreadSlot) { slot[self] := self; } else { saved := self; };
    goto all_run_L;
  } or {
    \* Py.Thread.call (STATE_ALL): D, then L released, G kept.
    await CanNest(self);
    spend(); depth[self] := depth[self] + 1;
    dropD(); st[self] := "PYTHON";
    goto all_call_unlock;
  } or {
    \* A tick of the systhreads of OCaml: at a safepoint, the thread yields
    \* D to another thread of its domain that waits for it, and waits to
    \* take it again, keeping L and G (OCaml does not know about them).
    await CanDo(self);
    spend(); dropD();
    goto all_yield;
  } or {
    \* Python code under D (conversions, __del__) that releases G.
    await PythonUnderD /\ CanDo(self);
    spend(); detach();
    goto all_pyd;
  } or {
    \* A collection of free-threaded Python started by such code.
    await PythonUnderD /\ FreeThreaded /\ CanDo(self) /\ pstw = None;
    spend(); pstw := self;
    goto all_pstw;
  } or {
    return;
  };
all_gc:
  await \A d \in Domains : SafeFor(d, self);
  ostw := None; goto all;
all_run_L:
  \* run_ocaml: L released after G.
  L := None;
all_run:
  call OCamlCode();
all_restore:
  \* Py.Thread.restore: caml_enter_blocking_section, L, G (the thread state
  \* detached by release: PyEval_RestoreThread(NULL) is a fatal error), D.
  depth[self] := depth[self] - 1;
  if (PerThreadSlot) {
    assert slot[self] # None;
    slot[self] := None;
  } else {
    assert saved # None;
    saved := None;
  };
  dropD();
all_restore_L:
  takeL();
all_restore_g:
  \* PyEval_RestoreThread (G), then caml_leave_blocking_section (D).
  attach();
all_restore_d:
  takeD(); st[self] := "ALL"; goto all;
all_call_unlock:
  \* Py.Thread.call: L released after D.
  L := None;
all_call:
  call PyCode();
all_call_back:
  \* lock_world_holding_gil, then caml_leave_blocking_section (D).
  depth[self] := depth[self] - 1;
  if (L = None) { L := self; goto all_call_d; } else { detach(); };
all_call_L:
  takeL();
all_call_g:
  attach();
all_call_d:
  takeD(); st[self] := "ALL"; goto all;
all_pyd:
  attach(); goto all;
all_yield:
  takeD(); goto all;
all_pstw:
  await attached = {self}; pstw := None; goto all;
}

\* OCaml code, holding D (and neither L nor G): in Py.Thread.run_ocaml
\* (STATE_OCAML), or in an OCaml thread or domain (STATE_UNKNOWN).
procedure OCamlCode() {
oc:
  await ostw \in {None, self};
  either {
    \* A minor collection.
    await CanDo(self) /\ ostw = None;
    spend(); ostw := self;
    goto oc_gc;
  } or {
    \* A blocking section (mutex, condition, Domain.join, I/O).
    await CanDo(self);
    spend();
    dropD();
    goto oc_bl_d;
  } or {
    \* Py.Thread.run_python: acquire. Py.Thread.call is run_python around
    \* the call of STATE_ALL (see AllCode).
    await CanNest(self);
    spend(); depth[self] := depth[self] + 1;
    if (st[self] = "OCAML") {
      \* caml_enter_blocking_section, L, PyGILState_Ensure (attaches the
      \* thread state detached by run_ocaml), caml_leave_blocking_section.
      dropD(); goto oc_rp_L1;
    } else {
      \* From STATE_UNKNOWN: caml_enter_blocking_section, L, then
      \* PyGILState_Ensure, then caml_leave_blocking_section.
      dropD(); goto oc_rp_L2;
    };
  } or {
    return;
  };
oc_gc:
  await \A d \in Domains : SafeFor(d, self);
  ostw := None; goto oc;
oc_bl_d:
  \* caml_leave_blocking_section: D (no hook, STATE_OCAML holds no Python
  \* lock).
  takeD();
  goto oc;
oc_rp_L1:
  takeL();
oc_rp_g1:
  attach();
oc_rp_d1:
  takeD(); st[self] := "ALL";
  call AllCode();
oc_rp_back1:
  \* unacquire: PyGILState_Release (G), back to STATE_OCAML, L released.
  depth[self] := depth[self] - 1;
  detach(); st[self] := "OCAML";
oc_rp_unlock1:
  \* unacquire: L released after G.
  L := None; goto oc;
oc_rp_L2:
  takeL();
oc_rp_g2:
  attach();
oc_rp_d2:
  takeD(); st[self] := "ALL";
  call AllCode();
oc_rp_back2:
  \* unacquire: PyGILState_Release, previous state, L released.
  depth[self] := depth[self] - 1;
  detach(); st[self] := "UNKNOWN";
oc_rp_unlock2:
  L := None; goto oc;
}

\* Weak fairness: every thread keeps running. Each switch of the GIL at the
\* eval breaker spends an operation, so that a thread cannot take the GIL
\* back forever while another one waits (CPython forces the switch of the
\* GIL to a waiting thread).
fair process (pyth \in PyThreads) {
p_start:
  if (self = P1) {
    \* pyml_thread_leave after caml_startup: D, then L released.
    dropD(); st[self] := "PYTHON";
    goto p_unlock;
  };
p_attach:
  attach();
  goto p_run;
p_unlock:
  \* pyml_thread_leave: L released after D.
  L := None;
p_run:
  call PyCode();
p_exit:
  detach();
}

fair process (othr \in OCamlThreads) {
o_start:
  takeD();
o_run:
  call OCamlCode();
o_exit:
  dropD();
}
} *)
\* BEGIN TRANSLATION (chksum(pcal) = "d23426c3" /\ chksum(tla) = "f9fec216")
VARIABLES pc, L, attached, D, st, registered, ostw, pstw, ops, depth, slot, 
          stack

(* define statement *)
CanAttach(t) == IF FreeThreaded THEN pstw \in {None, t} ELSE attached = {}
HoldsD(t) == D[Dom(t)] = t
CanDo(t) == ops[t] > 0
CanNest(t) == ops[t] > 0 /\ depth[t] < MaxDepth



SafeFor(d, t) ==
  IF D[d] = None \/ D[d] = t THEN TRUE ELSE pc[D[d]] \in {"all", "oc"}

VARIABLE saved

vars == << pc, L, attached, D, st, registered, ostw, pstw, ops, depth, slot, 
           stack, saved >>

ProcSet == (PyThreads) \cup (OCamlThreads)

Init == (* Global variables *)
        /\ L = P1
        /\ attached = {P1}
        /\ D = [d \in Domains |-> IF d = 1 THEN P1 ELSE None]
        /\ st = [t \in Threads |-> IF t = P1 THEN "ALL" ELSE "UNKNOWN"]
        /\ registered = [t \in Threads |-> t = P1 \/ t \in OCamlThreads]
        /\ ostw = None
        /\ pstw = None
        /\ ops = [t \in Threads |-> MaxOps]
        /\ depth = [t \in Threads |-> 0]
        /\ slot = [t \in Threads |-> None]
        (* Procedure AllCode *)
        /\ saved = [ self \in ProcSet |-> None]
        /\ stack = [self \in ProcSet |-> << >>]
        /\ pc = [self \in ProcSet |-> CASE self \in PyThreads -> "p_start"
                                        [] self \in OCamlThreads -> "o_start"]

py(self) == /\ pc[self] = "py"
            /\ \/ /\ CanDo(self)
                  /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                  /\ attached' = attached \ {self}
                  /\ pc' = [pc EXCEPT ![self] = "py_reattach"]
                  /\ UNCHANGED <<pstw, depth, stack>>
               \/ /\ FreeThreaded /\ CanDo(self) /\ pstw = None
                  /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                  /\ pstw' = self
                  /\ pc' = [pc EXCEPT ![self] = "py_pstw"]
                  /\ UNCHANGED <<attached, depth, stack>>
               \/ /\ CanNest(self)
                  /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                  /\ depth' = [depth EXCEPT ![self] = depth[self] + 1]
                  /\ IF registered[self]
                        THEN /\ pc' = [pc EXCEPT ![self] = "py_lockL"]
                             /\ UNCHANGED attached
                        ELSE /\ attached' = attached \ {self}
                             /\ pc' = [pc EXCEPT ![self] = "py_reg_d"]
                  /\ UNCHANGED <<pstw, stack>>
               \/ /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                  /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                  /\ UNCHANGED <<attached, pstw, ops, depth>>
            /\ UNCHANGED << L, D, st, registered, ostw, slot, saved >>

py_reattach(self) == /\ pc[self] = "py_reattach"
                     /\ CanAttach(self)
                     /\ Assert(L = self \/ ~HoldsD(self), 
                               "Failure of assertion at line 90, column 3 of macro called at line 130, column 3.")
                     /\ attached' = (attached \cup {self})
                     /\ pc' = [pc EXCEPT ![self] = "py"]
                     /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, 
                                     depth, slot, stack, saved >>

py_pstw(self) == /\ pc[self] = "py_pstw"
                 /\ attached = {self}
                 /\ pstw' = None
                 /\ pc' = [pc EXCEPT ![self] = "py"]
                 /\ UNCHANGED << L, attached, D, st, registered, ostw, ops, 
                                 depth, slot, stack, saved >>

py_reg_d(self) == /\ pc[self] = "py_reg_d"
                  /\ D[Dom(self)] = None
                  /\ D' = [D EXCEPT ![Dom(self)] = self]
                  /\ pc' = [pc EXCEPT ![self] = "py_reg_undo"]
                  /\ UNCHANGED << L, attached, st, registered, ostw, pstw, ops, 
                                  depth, slot, stack, saved >>

py_reg_undo(self) == /\ pc[self] = "py_reg_undo"
                     /\ D' = [D EXCEPT ![Dom(self)] = None]
                     /\ registered' = [registered EXCEPT ![self] = TRUE]
                     /\ pc' = [pc EXCEPT ![self] = "py_reg_g"]
                     /\ UNCHANGED << L, attached, st, ostw, pstw, ops, depth, 
                                     slot, stack, saved >>

py_reg_g(self) == /\ pc[self] = "py_reg_g"
                  /\ CanAttach(self)
                  /\ Assert(L = self \/ ~HoldsD(self), 
                            "Failure of assertion at line 90, column 3 of macro called at line 138, column 3.")
                  /\ attached' = (attached \cup {self})
                  /\ pc' = [pc EXCEPT ![self] = "py_lockL"]
                  /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                                  slot, stack, saved >>

py_lockL(self) == /\ pc[self] = "py_lockL"
                  /\ IF L = None
                        THEN /\ L' = self
                             /\ pc' = [pc EXCEPT ![self] = "py_d"]
                             /\ UNCHANGED attached
                        ELSE /\ attached' = attached \ {self}
                             /\ pc' = [pc EXCEPT ![self] = "py_waitL"]
                             /\ L' = L
                  /\ UNCHANGED << D, st, registered, ostw, pstw, ops, depth, 
                                  slot, stack, saved >>

py_waitL(self) == /\ pc[self] = "py_waitL"
                  /\ L = None
                  /\ Assert(self \notin attached /\ ~HoldsD(self), 
                            "Failure of assertion at line 95, column 3 of macro called at line 143, column 3.")
                  /\ L' = self
                  /\ pc' = [pc EXCEPT ![self] = "py_g"]
                  /\ UNCHANGED << attached, D, st, registered, ostw, pstw, ops, 
                                  depth, slot, stack, saved >>

py_g(self) == /\ pc[self] = "py_g"
              /\ CanAttach(self)
              /\ Assert(L = self \/ ~HoldsD(self), 
                        "Failure of assertion at line 90, column 3 of macro called at line 145, column 3.")
              /\ attached' = (attached \cup {self})
              /\ pc' = [pc EXCEPT ![self] = "py_d"]
              /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                              slot, stack, saved >>

py_d(self) == /\ pc[self] = "py_d"
              /\ D[Dom(self)] = None
              /\ D' = [D EXCEPT ![Dom(self)] = self]
              /\ st' = [st EXCEPT ![self] = "ALL"]
              /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "AllCode",
                                                       pc        |->  "py_leave",
                                                       saved     |->  saved[self] ] >>
                                                   \o stack[self]]
              /\ saved' = [saved EXCEPT ![self] = None]
              /\ pc' = [pc EXCEPT ![self] = "all"]
              /\ UNCHANGED << L, attached, registered, ostw, pstw, ops, depth, 
                              slot >>

py_leave(self) == /\ pc[self] = "py_leave"
                  /\ D' = [D EXCEPT ![Dom(self)] = None]
                  /\ st' = [st EXCEPT ![self] = "PYTHON"]
                  /\ depth' = [depth EXCEPT ![self] = depth[self] - 1]
                  /\ pc' = [pc EXCEPT ![self] = "py_leave_L"]
                  /\ UNCHANGED << L, attached, registered, ostw, pstw, ops, 
                                  slot, stack, saved >>

py_leave_L(self) == /\ pc[self] = "py_leave_L"
                    /\ L' = None
                    /\ pc' = [pc EXCEPT ![self] = "py"]
                    /\ UNCHANGED << attached, D, st, registered, ostw, pstw, 
                                    ops, depth, slot, stack, saved >>

PyCode(self) == py(self) \/ py_reattach(self) \/ py_pstw(self)
                   \/ py_reg_d(self) \/ py_reg_undo(self) \/ py_reg_g(self)
                   \/ py_lockL(self) \/ py_waitL(self) \/ py_g(self)
                   \/ py_d(self) \/ py_leave(self) \/ py_leave_L(self)

all(self) == /\ pc[self] = "all"
             /\ ostw \in {None, self}
             /\ \/ /\ CanDo(self) /\ ostw = None
                   /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                   /\ ostw' = self
                   /\ pc' = [pc EXCEPT ![self] = "all_gc"]
                   /\ UNCHANGED <<attached, D, st, pstw, depth, slot, stack, saved>>
                \/ /\ CanNest(self)
                   /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                   /\ depth' = [depth EXCEPT ![self] = depth[self] + 1]
                   /\ attached' = attached \ {self}
                   /\ st' = [st EXCEPT ![self] = "OCAML"]
                   /\ IF PerThreadSlot
                         THEN /\ slot' = [slot EXCEPT ![self] = self]
                              /\ saved' = saved
                         ELSE /\ saved' = [saved EXCEPT ![self] = self]
                              /\ slot' = slot
                   /\ pc' = [pc EXCEPT ![self] = "all_run_L"]
                   /\ UNCHANGED <<D, ostw, pstw, stack>>
                \/ /\ CanNest(self)
                   /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                   /\ depth' = [depth EXCEPT ![self] = depth[self] + 1]
                   /\ D' = [D EXCEPT ![Dom(self)] = None]
                   /\ st' = [st EXCEPT ![self] = "PYTHON"]
                   /\ pc' = [pc EXCEPT ![self] = "all_call_unlock"]
                   /\ UNCHANGED <<attached, ostw, pstw, slot, stack, saved>>
                \/ /\ CanDo(self)
                   /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                   /\ D' = [D EXCEPT ![Dom(self)] = None]
                   /\ pc' = [pc EXCEPT ![self] = "all_yield"]
                   /\ UNCHANGED <<attached, st, ostw, pstw, depth, slot, stack, saved>>
                \/ /\ PythonUnderD /\ CanDo(self)
                   /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                   /\ attached' = attached \ {self}
                   /\ pc' = [pc EXCEPT ![self] = "all_pyd"]
                   /\ UNCHANGED <<D, st, ostw, pstw, depth, slot, stack, saved>>
                \/ /\ PythonUnderD /\ FreeThreaded /\ CanDo(self) /\ pstw = None
                   /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                   /\ pstw' = self
                   /\ pc' = [pc EXCEPT ![self] = "all_pstw"]
                   /\ UNCHANGED <<attached, D, st, ostw, depth, slot, stack, saved>>
                \/ /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                   /\ saved' = [saved EXCEPT ![self] = Head(stack[self]).saved]
                   /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                   /\ UNCHANGED <<attached, D, st, ostw, pstw, ops, depth, slot>>
             /\ UNCHANGED << L, registered >>

all_gc(self) == /\ pc[self] = "all_gc"
                /\ \A d \in Domains : SafeFor(d, self)
                /\ ostw' = None
                /\ pc' = [pc EXCEPT ![self] = "all"]
                /\ UNCHANGED << L, attached, D, st, registered, pstw, ops, 
                                depth, slot, stack, saved >>

all_run_L(self) == /\ pc[self] = "all_run_L"
                   /\ L' = None
                   /\ pc' = [pc EXCEPT ![self] = "all_run"]
                   /\ UNCHANGED << attached, D, st, registered, ostw, pstw, 
                                   ops, depth, slot, stack, saved >>

all_run(self) == /\ pc[self] = "all_run"
                 /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "OCamlCode",
                                                          pc        |->  "all_restore" ] >>
                                                      \o stack[self]]
                 /\ pc' = [pc EXCEPT ![self] = "oc"]
                 /\ UNCHANGED << L, attached, D, st, registered, ostw, pstw, 
                                 ops, depth, slot, saved >>

all_restore(self) == /\ pc[self] = "all_restore"
                     /\ depth' = [depth EXCEPT ![self] = depth[self] - 1]
                     /\ IF PerThreadSlot
                           THEN /\ Assert(slot[self] # None, 
                                          "Failure of assertion at line 222, column 5.")
                                /\ slot' = [slot EXCEPT ![self] = None]
                                /\ saved' = saved
                           ELSE /\ Assert(saved[self] # None, 
                                          "Failure of assertion at line 225, column 5.")
                                /\ saved' = [saved EXCEPT ![self] = None]
                                /\ slot' = slot
                     /\ D' = [D EXCEPT ![Dom(self)] = None]
                     /\ pc' = [pc EXCEPT ![self] = "all_restore_L"]
                     /\ UNCHANGED << L, attached, st, registered, ostw, pstw, 
                                     ops, stack >>

all_restore_L(self) == /\ pc[self] = "all_restore_L"
                       /\ L = None
                       /\ Assert(self \notin attached /\ ~HoldsD(self), 
                                 "Failure of assertion at line 95, column 3 of macro called at line 230, column 3.")
                       /\ L' = self
                       /\ pc' = [pc EXCEPT ![self] = "all_restore_g"]
                       /\ UNCHANGED << attached, D, st, registered, ostw, pstw, 
                                       ops, depth, slot, stack, saved >>

all_restore_g(self) == /\ pc[self] = "all_restore_g"
                       /\ CanAttach(self)
                       /\ Assert(L = self \/ ~HoldsD(self), 
                                 "Failure of assertion at line 90, column 3 of macro called at line 233, column 3.")
                       /\ attached' = (attached \cup {self})
                       /\ pc' = [pc EXCEPT ![self] = "all_restore_d"]
                       /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, 
                                       depth, slot, stack, saved >>

all_restore_d(self) == /\ pc[self] = "all_restore_d"
                       /\ D[Dom(self)] = None
                       /\ D' = [D EXCEPT ![Dom(self)] = self]
                       /\ st' = [st EXCEPT ![self] = "ALL"]
                       /\ pc' = [pc EXCEPT ![self] = "all"]
                       /\ UNCHANGED << L, attached, registered, ostw, pstw, 
                                       ops, depth, slot, stack, saved >>

all_call_unlock(self) == /\ pc[self] = "all_call_unlock"
                         /\ L' = None
                         /\ pc' = [pc EXCEPT ![self] = "all_call"]
                         /\ UNCHANGED << attached, D, st, registered, ostw, 
                                         pstw, ops, depth, slot, stack, saved >>

all_call(self) == /\ pc[self] = "all_call"
                  /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "PyCode",
                                                           pc        |->  "all_call_back" ] >>
                                                       \o stack[self]]
                  /\ pc' = [pc EXCEPT ![self] = "py"]
                  /\ UNCHANGED << L, attached, D, st, registered, ostw, pstw, 
                                  ops, depth, slot, saved >>

all_call_back(self) == /\ pc[self] = "all_call_back"
                       /\ depth' = [depth EXCEPT ![self] = depth[self] - 1]
                       /\ IF L = None
                             THEN /\ L' = self
                                  /\ pc' = [pc EXCEPT ![self] = "all_call_d"]
                                  /\ UNCHANGED attached
                             ELSE /\ attached' = attached \ {self}
                                  /\ pc' = [pc EXCEPT ![self] = "all_call_L"]
                                  /\ L' = L
                       /\ UNCHANGED << D, st, registered, ostw, pstw, ops, 
                                       slot, stack, saved >>

all_call_L(self) == /\ pc[self] = "all_call_L"
                    /\ L = None
                    /\ Assert(self \notin attached /\ ~HoldsD(self), 
                              "Failure of assertion at line 95, column 3 of macro called at line 246, column 3.")
                    /\ L' = self
                    /\ pc' = [pc EXCEPT ![self] = "all_call_g"]
                    /\ UNCHANGED << attached, D, st, registered, ostw, pstw, 
                                    ops, depth, slot, stack, saved >>

all_call_g(self) == /\ pc[self] = "all_call_g"
                    /\ CanAttach(self)
                    /\ Assert(L = self \/ ~HoldsD(self), 
                              "Failure of assertion at line 90, column 3 of macro called at line 248, column 3.")
                    /\ attached' = (attached \cup {self})
                    /\ pc' = [pc EXCEPT ![self] = "all_call_d"]
                    /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, 
                                    depth, slot, stack, saved >>

all_call_d(self) == /\ pc[self] = "all_call_d"
                    /\ D[Dom(self)] = None
                    /\ D' = [D EXCEPT ![Dom(self)] = self]
                    /\ st' = [st EXCEPT ![self] = "ALL"]
                    /\ pc' = [pc EXCEPT ![self] = "all"]
                    /\ UNCHANGED << L, attached, registered, ostw, pstw, ops, 
                                    depth, slot, stack, saved >>

all_pyd(self) == /\ pc[self] = "all_pyd"
                 /\ CanAttach(self)
                 /\ Assert(L = self \/ ~HoldsD(self), 
                           "Failure of assertion at line 90, column 3 of macro called at line 252, column 3.")
                 /\ attached' = (attached \cup {self})
                 /\ pc' = [pc EXCEPT ![self] = "all"]
                 /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                                 slot, stack, saved >>

all_yield(self) == /\ pc[self] = "all_yield"
                   /\ D[Dom(self)] = None
                   /\ D' = [D EXCEPT ![Dom(self)] = self]
                   /\ pc' = [pc EXCEPT ![self] = "all"]
                   /\ UNCHANGED << L, attached, st, registered, ostw, pstw, 
                                   ops, depth, slot, stack, saved >>

all_pstw(self) == /\ pc[self] = "all_pstw"
                  /\ attached = {self}
                  /\ pstw' = None
                  /\ pc' = [pc EXCEPT ![self] = "all"]
                  /\ UNCHANGED << L, attached, D, st, registered, ostw, ops, 
                                  depth, slot, stack, saved >>

AllCode(self) == all(self) \/ all_gc(self) \/ all_run_L(self)
                    \/ all_run(self) \/ all_restore(self)
                    \/ all_restore_L(self) \/ all_restore_g(self)
                    \/ all_restore_d(self) \/ all_call_unlock(self)
                    \/ all_call(self) \/ all_call_back(self)
                    \/ all_call_L(self) \/ all_call_g(self)
                    \/ all_call_d(self) \/ all_pyd(self) \/ all_yield(self)
                    \/ all_pstw(self)

oc(self) == /\ pc[self] = "oc"
            /\ ostw \in {None, self}
            /\ \/ /\ CanDo(self) /\ ostw = None
                  /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                  /\ ostw' = self
                  /\ pc' = [pc EXCEPT ![self] = "oc_gc"]
                  /\ UNCHANGED <<D, depth, stack>>
               \/ /\ CanDo(self)
                  /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                  /\ D' = [D EXCEPT ![Dom(self)] = None]
                  /\ pc' = [pc EXCEPT ![self] = "oc_bl_d"]
                  /\ UNCHANGED <<ostw, depth, stack>>
               \/ /\ CanNest(self)
                  /\ ops' = [ops EXCEPT ![self] = ops[self] - 1]
                  /\ depth' = [depth EXCEPT ![self] = depth[self] + 1]
                  /\ IF st[self] = "OCAML"
                        THEN /\ D' = [D EXCEPT ![Dom(self)] = None]
                             /\ pc' = [pc EXCEPT ![self] = "oc_rp_L1"]
                        ELSE /\ D' = [D EXCEPT ![Dom(self)] = None]
                             /\ pc' = [pc EXCEPT ![self] = "oc_rp_L2"]
                  /\ UNCHANGED <<ostw, stack>>
               \/ /\ pc' = [pc EXCEPT ![self] = Head(stack[self]).pc]
                  /\ stack' = [stack EXCEPT ![self] = Tail(stack[self])]
                  /\ UNCHANGED <<D, ostw, ops, depth>>
            /\ UNCHANGED << L, attached, st, registered, pstw, slot, saved >>

oc_gc(self) == /\ pc[self] = "oc_gc"
               /\ \A d \in Domains : SafeFor(d, self)
               /\ ostw' = None
               /\ pc' = [pc EXCEPT ![self] = "oc"]
               /\ UNCHANGED << L, attached, D, st, registered, pstw, ops, 
                               depth, slot, stack, saved >>

oc_bl_d(self) == /\ pc[self] = "oc_bl_d"
                 /\ D[Dom(self)] = None
                 /\ D' = [D EXCEPT ![Dom(self)] = self]
                 /\ pc' = [pc EXCEPT ![self] = "oc"]
                 /\ UNCHANGED << L, attached, st, registered, ostw, pstw, ops, 
                                 depth, slot, stack, saved >>

oc_rp_L1(self) == /\ pc[self] = "oc_rp_L1"
                  /\ L = None
                  /\ Assert(self \notin attached /\ ~HoldsD(self), 
                            "Failure of assertion at line 95, column 3 of macro called at line 301, column 3.")
                  /\ L' = self
                  /\ pc' = [pc EXCEPT ![self] = "oc_rp_g1"]
                  /\ UNCHANGED << attached, D, st, registered, ostw, pstw, ops, 
                                  depth, slot, stack, saved >>

oc_rp_g1(self) == /\ pc[self] = "oc_rp_g1"
                  /\ CanAttach(self)
                  /\ Assert(L = self \/ ~HoldsD(self), 
                            "Failure of assertion at line 90, column 3 of macro called at line 303, column 3.")
                  /\ attached' = (attached \cup {self})
                  /\ pc' = [pc EXCEPT ![self] = "oc_rp_d1"]
                  /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                                  slot, stack, saved >>

oc_rp_d1(self) == /\ pc[self] = "oc_rp_d1"
                  /\ D[Dom(self)] = None
                  /\ D' = [D EXCEPT ![Dom(self)] = self]
                  /\ st' = [st EXCEPT ![self] = "ALL"]
                  /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "AllCode",
                                                           pc        |->  "oc_rp_back1",
                                                           saved     |->  saved[self] ] >>
                                                       \o stack[self]]
                  /\ saved' = [saved EXCEPT ![self] = None]
                  /\ pc' = [pc EXCEPT ![self] = "all"]
                  /\ UNCHANGED << L, attached, registered, ostw, pstw, ops, 
                                  depth, slot >>

oc_rp_back1(self) == /\ pc[self] = "oc_rp_back1"
                     /\ depth' = [depth EXCEPT ![self] = depth[self] - 1]
                     /\ attached' = attached \ {self}
                     /\ st' = [st EXCEPT ![self] = "OCAML"]
                     /\ pc' = [pc EXCEPT ![self] = "oc_rp_unlock1"]
                     /\ UNCHANGED << L, D, registered, ostw, pstw, ops, slot, 
                                     stack, saved >>

oc_rp_unlock1(self) == /\ pc[self] = "oc_rp_unlock1"
                       /\ L' = None
                       /\ pc' = [pc EXCEPT ![self] = "oc"]
                       /\ UNCHANGED << attached, D, st, registered, ostw, pstw, 
                                       ops, depth, slot, stack, saved >>

oc_rp_L2(self) == /\ pc[self] = "oc_rp_L2"
                  /\ L = None
                  /\ Assert(self \notin attached /\ ~HoldsD(self), 
                            "Failure of assertion at line 95, column 3 of macro called at line 315, column 3.")
                  /\ L' = self
                  /\ pc' = [pc EXCEPT ![self] = "oc_rp_g2"]
                  /\ UNCHANGED << attached, D, st, registered, ostw, pstw, ops, 
                                  depth, slot, stack, saved >>

oc_rp_g2(self) == /\ pc[self] = "oc_rp_g2"
                  /\ CanAttach(self)
                  /\ Assert(L = self \/ ~HoldsD(self), 
                            "Failure of assertion at line 90, column 3 of macro called at line 317, column 3.")
                  /\ attached' = (attached \cup {self})
                  /\ pc' = [pc EXCEPT ![self] = "oc_rp_d2"]
                  /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                                  slot, stack, saved >>

oc_rp_d2(self) == /\ pc[self] = "oc_rp_d2"
                  /\ D[Dom(self)] = None
                  /\ D' = [D EXCEPT ![Dom(self)] = self]
                  /\ st' = [st EXCEPT ![self] = "ALL"]
                  /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "AllCode",
                                                           pc        |->  "oc_rp_back2",
                                                           saved     |->  saved[self] ] >>
                                                       \o stack[self]]
                  /\ saved' = [saved EXCEPT ![self] = None]
                  /\ pc' = [pc EXCEPT ![self] = "all"]
                  /\ UNCHANGED << L, attached, registered, ostw, pstw, ops, 
                                  depth, slot >>

oc_rp_back2(self) == /\ pc[self] = "oc_rp_back2"
                     /\ depth' = [depth EXCEPT ![self] = depth[self] - 1]
                     /\ attached' = attached \ {self}
                     /\ st' = [st EXCEPT ![self] = "UNKNOWN"]
                     /\ pc' = [pc EXCEPT ![self] = "oc_rp_unlock2"]
                     /\ UNCHANGED << L, D, registered, ostw, pstw, ops, slot, 
                                     stack, saved >>

oc_rp_unlock2(self) == /\ pc[self] = "oc_rp_unlock2"
                       /\ L' = None
                       /\ pc' = [pc EXCEPT ![self] = "oc"]
                       /\ UNCHANGED << attached, D, st, registered, ostw, pstw, 
                                       ops, depth, slot, stack, saved >>

OCamlCode(self) == oc(self) \/ oc_gc(self) \/ oc_bl_d(self)
                      \/ oc_rp_L1(self) \/ oc_rp_g1(self) \/ oc_rp_d1(self)
                      \/ oc_rp_back1(self) \/ oc_rp_unlock1(self)
                      \/ oc_rp_L2(self) \/ oc_rp_g2(self) \/ oc_rp_d2(self)
                      \/ oc_rp_back2(self) \/ oc_rp_unlock2(self)

p_start(self) == /\ pc[self] = "p_start"
                 /\ IF self = P1
                       THEN /\ D' = [D EXCEPT ![Dom(self)] = None]
                            /\ st' = [st EXCEPT ![self] = "PYTHON"]
                            /\ pc' = [pc EXCEPT ![self] = "p_unlock"]
                       ELSE /\ pc' = [pc EXCEPT ![self] = "p_attach"]
                            /\ UNCHANGED << D, st >>
                 /\ UNCHANGED << L, attached, registered, ostw, pstw, ops, 
                                 depth, slot, stack, saved >>

p_attach(self) == /\ pc[self] = "p_attach"
                  /\ CanAttach(self)
                  /\ Assert(L = self \/ ~HoldsD(self), 
                            "Failure of assertion at line 90, column 3 of macro called at line 341, column 3.")
                  /\ attached' = (attached \cup {self})
                  /\ pc' = [pc EXCEPT ![self] = "p_run"]
                  /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                                  slot, stack, saved >>

p_unlock(self) == /\ pc[self] = "p_unlock"
                  /\ L' = None
                  /\ pc' = [pc EXCEPT ![self] = "p_run"]
                  /\ UNCHANGED << attached, D, st, registered, ostw, pstw, ops, 
                                  depth, slot, stack, saved >>

p_run(self) == /\ pc[self] = "p_run"
               /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "PyCode",
                                                        pc        |->  "p_exit" ] >>
                                                    \o stack[self]]
               /\ pc' = [pc EXCEPT ![self] = "py"]
               /\ UNCHANGED << L, attached, D, st, registered, ostw, pstw, ops, 
                               depth, slot, saved >>

p_exit(self) == /\ pc[self] = "p_exit"
                /\ attached' = attached \ {self}
                /\ pc' = [pc EXCEPT ![self] = "Done"]
                /\ UNCHANGED << L, D, st, registered, ostw, pstw, ops, depth, 
                                slot, stack, saved >>

pyth(self) == p_start(self) \/ p_attach(self) \/ p_unlock(self)
                 \/ p_run(self) \/ p_exit(self)

o_start(self) == /\ pc[self] = "o_start"
                 /\ D[Dom(self)] = None
                 /\ D' = [D EXCEPT ![Dom(self)] = self]
                 /\ pc' = [pc EXCEPT ![self] = "o_run"]
                 /\ UNCHANGED << L, attached, st, registered, ostw, pstw, ops, 
                                 depth, slot, stack, saved >>

o_run(self) == /\ pc[self] = "o_run"
               /\ stack' = [stack EXCEPT ![self] = << [ procedure |->  "OCamlCode",
                                                        pc        |->  "o_exit" ] >>
                                                    \o stack[self]]
               /\ pc' = [pc EXCEPT ![self] = "oc"]
               /\ UNCHANGED << L, attached, D, st, registered, ostw, pstw, ops, 
                               depth, slot, saved >>

o_exit(self) == /\ pc[self] = "o_exit"
                /\ D' = [D EXCEPT ![Dom(self)] = None]
                /\ pc' = [pc EXCEPT ![self] = "Done"]
                /\ UNCHANGED << L, attached, st, registered, ostw, pstw, ops, 
                                depth, slot, stack, saved >>

othr(self) == o_start(self) \/ o_run(self) \/ o_exit(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == (\E self \in ProcSet:  \/ PyCode(self) \/ AllCode(self)
                               \/ OCamlCode(self))
           \/ (\E self \in PyThreads: pyth(self))
           \/ (\E self \in OCamlThreads: othr(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in PyThreads : /\ WF_vars(pyth(self))
                                   /\ WF_vars(PyCode(self))
                                   /\ WF_vars(AllCode(self))
                                   /\ WF_vars(OCamlCode(self))
        /\ \A self \in OCamlThreads : /\ WF_vars(othr(self))
                                      /\ WF_vars(OCamlCode(self))
                                      /\ WF_vars(PyCode(self))
                                      /\ WF_vars(AllCode(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 
\* END TRANSLATION 
\* END TRANSLATION 
\* END TRANSLATION 

\* END TRANSLATION

-----------------------------------------------------------------------------
(* Properties *)

\* The GIL is held by one thread at most.
GILExclusive == ~FreeThreaded => Cardinality(attached) <= 1


\* Python code runs with G; the code of ocip with L, G and D; OCaml code
\* with D only (in run_ocaml too: it uses the Python API in run_python).
PythonHasG == \A t \in Threads : pc[t] = "py" => t \in attached
OcipHasAll ==
  \A t \in Threads :
    pc[t] = "all" => L = t /\ t \in attached /\ HoldsD(t) /\ st[t] = "ALL"
OCamlHasD ==
  \A t \in Threads :
    pc[t] = "oc" =>
      HoldsD(t) /\ t \notin attached /\ L # t
                /\ st[t] \in {"OCAML", "UNKNOWN"}

\* (The order of the locks is checked by the assertions of attach and
\* takeL.)
Safety == GILExclusive /\ PythonHasG /\ OcipHasAll /\ OCamlHasD

=============================================================================
