# A TLA+ model of the locks of `Py.Thread`

`PymlThreads.tla` models how pyml's `Py.Thread` handles locks when a Python
program loads an OCaml library that uses pyml (as ocip does: Python threads
call OCaml, and OCaml threads and domains call Python). It is a PlusCal
algorithm, translated to TLA+ in the same file. It follows pyml at 8fe89a7
(merge request tmartine/pyml!4, branch `threads-fix-deadlock`): see the
comment "Threads" in `pyml_stubs.c`.

The same files are in `tla/` of pyml (branch `threads-fix-deadlock`) and of
ocip (branch `tla-threads`).

## What is modeled

- The locks:
  - L, the world lock of pyml (the OCaml code that uses the Python API
    holds it);
  - G, the GIL, or the set of attached thread states for free-threaded
    Python;
  - D[d], the lock of each OCaml domain.
- The thread states that `Py.Thread.run_ocaml` detaches: `release` returns
  the thread state, and `restore` attaches it again. The value is local to
  the call of `run_ocaml` (the variable `saved` of `AllCode`), or, with
  `PerThreadSlot = TRUE`, kept in one slot per thread, as pyml did before
  8fe89a7.
- The stop-the-world sections:
  - OCaml's minor collections, which wait until the holder of each held
    domain lock reaches a safepoint (the labels `all` and `oc`);
  - the collections of free-threaded Python, which wait until every other
    thread has detached.
- The threads:
  - Python threads (in domain 1). `p1` is the thread that loaded the OCaml
    library: it starts with L, G and D, as after `Py.Thread.enable`, and
    releases L and D with `pyml_thread_leave`. The other Python threads
    register in the OCaml runtime on their first call.
  - OCaml threads and domains (`o1`: a systhread of domain 1; `o2`: a
    second domain).
- The paths of the code, one procedure each, with an atomic step at each
  lock acquisition and at each release (as in the code, where another
  thread can take a lock between two releases):
  - `PyCode` is Python code. It calls OCaml with
    `pyml_threads_enter_from_python`/`leave_to_python`, switches the GIL at
    the eval breaker, and can start a Python stop-the-world.
  - `AllCode` is `STATE_ALL`: the OCaml code called by Python, which holds
    L, G and D and uses the Python API (for ocip, its conversions and
    lookups). It does `Py.Thread.run_ocaml` (`release`/`restore`),
    `Py.Thread.call` and minor collections, and yields D at the ticks of
    the systhreads (a thread waiting for the lock of the domain takes it,
    while L and G stay held).
  - `OCamlCode` is the OCaml code in `run_ocaml` (`STATE_OCAML`) or in
    OCaml threads (`STATE_UNKNOWN`). It holds D only. It does blocking
    sections (which also stand for the ticks of the systhreads: D is
    released and taken again), `Py.Thread.run_python`
    (`acquire`/`unacquire`) and minor
    collections. `Py.Thread.call` there is `run_python` around the call of
    `STATE_ALL`, as in `py.ml`.

The constant `PythonUnderD` adds Python code that runs while D is held and
gives up G meanwhile: conversions, `__del__`, and the comparison and hash of
Python objects. Such code runs only in `STATE_ALL` (the Python API raises
`Failure` in `run_ocaml`, which does not release the locks in comparisons
and hashes), and the configs enable it.

## Properties

- The lock order L, G, D, checked by assertions in the macros that take
  the locks (`attach`, `takeL`) rather than by label names, so that a
  change in the code paths cannot slip past it: no thread takes G while it
  holds D, except the holder of L (the Python code under D in `STATE_ALL`),
  and no thread takes L while it holds G or D.
- `restore` attaches a thread state (an assertion:
  `PyEval_RestoreThread(NULL)` is a fatal error of Python).
- `Safety` (invariant):
  - the GIL is exclusive (without free threading);
  - Python code holds G; the code of `STATE_ALL` holds L, G and D; OCaml
    code holds D, and neither L nor G.
- Deadlock freedom: TLC's default check.
- `Termination` (under weak fairness): every thread completes its bounded
  number of operations, so every wait for a lock or a stop-the-world ends.
  Each switch of the GIL at the eval breaker costs an operation, which
  stands for CPython forcing the GIL over to a waiting thread.

## Configurations

Every config has two Python threads (`p1`, `p2`), `PythonUnderD = TRUE`
and `PerThreadSlot = FALSE`.

| Config | Python | OCaml actors | `MaxOps` | `MaxDepth` | Checks |
|---|---|---|---|---|---|
| `gil.cfg` | GIL | `o1` (domain 1), `o2` (domain 2) | 3 | 3 | safety, deadlock |
| `ft.cfg` | free-threaded | `o1`, `o2` | 3 | 3 | safety, deadlock |
| `gil_live.cfg` | GIL | `o1`, `o2` | 3 | 3 | safety, deadlock, `Termination` |
| `ft_live.cfg` | free-threaded | `o1`, `o2` | 3 | 3 | safety, deadlock, `Termination` |
| `gil_deep.cfg` | GIL | `o2` | 4 | 4 | safety, deadlock |
| `ft_deep.cfg` | free-threaded | `o2` | 4 | 4 | safety, deadlock |

Each call between OCaml and Python (and `run_ocaml`, `run_python`) nests
one level and costs one operation. `run_python` from `run_ocaml` needs
three levels: a Python thread calls OCaml, which enters `run_ocaml` and
calls `run_python` (an OCaml thread: `run_python`, `run_ocaml`,
`run_python`). With `MaxDepth = 2`, an invariant `pc[t] # "oc_rp_L1"`
holds on all the 6.1 million states of `MaxOps = 3`, and fails after 719
states with `MaxDepth = 3`. `run_ocaml` nested in itself (through
`run_python` and a call of OCaml by Python) and `Py.Thread.call` from
`run_ocaml` need a fourth level: the `*_deep` configs.

## Results (TLA+ Tools 2.0, nightly of 2026-11-06, 4 cores)

| Config | Result | Distinct states | Time |
|---|---|---|---|
| `gil.cfg` | no error | 10,711,015 | 1 min 37 s |
| `ft.cfg` | no error | 28,251,381 | 4 min 59 s |
| `gil_deep.cfg` | no error | 1,535,666 | 13 s |
| `ft_deep.cfg` | no error | 3,185,666 | 28 s |
| `gil_live.cfg` | no error, `Termination` holds | 10,711,015 | 14 min 10 s |
| `ft_live.cfg` | no error, `Termination` holds | 28,251,381 | 46 min 12 s |

The model before the refinements of the validation against executions
(74b7a1e, without the ticks and with two releases in some steps) passes
the same configurations, with 9,029,348 (`gil`) and 23,128,960 (`ft`)
distinct states, including the liveness configs (0d97da1, on 20 cores:
7 min 28 s and 22 min 47 s).

Mutants check that the model is not vacuous (checked before the
validation against executions refined the releases and added the ticks).
Each is a copy of the spec
with one bug, checked with `gil.cfg`, and TLC rejects each one, also
without the invariant `OCamlHasD` (that is, by the lock order or by a
deadlock):

| Mutant | Bug | Found by | Without `OCamlHasD` |
|---|---|---|---|
| N1 | `run_ocaml` keeps G (the protocol before afca177) | `Safety` (`OCamlHasD`) | assertion of `takeL` (`run_python` from `run_ocaml`, which needs `MaxDepth = 3`) |
| N2 | `restore` takes G before L | assertion of `takeL` | same |
| N3 | `run_ocaml` keeps L | `Safety` (`OCamlHasD`) | deadlock |
| N4 | `lock_world_holding_gil` waits for L while holding G | deadlock | same |

## The bugs that the model finds

### Nested `run_ocaml` (pyml e589efd, fixed by 8fe89a7)

`run_ocaml` kept the thread state that it detached in one slot per thread,
which `restore` emptied. With `PerThreadSlot = TRUE`, `gil_deep.cfg` fails
the assertion of `restore` after 126,872 states,
with a trace where only `p1` runs: it calls OCaml, which enters
`run_ocaml` and calls `run_python`, whose OCaml code enters `run_ocaml`
again; the inner `restore` empties the slot, and the outer one restores
NULL. This is the crash of ocip's `test_raise_from_python` (an OCaml
callback raises an OCaml exception, which ocip builds by calling OCaml).
`gil.cfg` (`MaxDepth = 3`) does not find it:
the bug needs four levels of nesting. The first versions of the model did
not have the thread states: G was only the set of the attached threads.

### Python code under D (pyml f134da0, fixed by afca177, tmartine/pyml#1)

The model of f134da0 is `PymlThreads.tla` at ocip's 83a65aa. There,
`STATE_OCAML` held G and D, the hooks of the blocking sections in
`run_ocaml` took G, then D, and Python code could run directly in
`run_ocaml`:

| Config of 83a65aa | `PythonUnderD` | `MaxOps`/`MaxDepth` | Result | Distinct states |
|---|---|---|---|---|
| `gil.cfg` | FALSE | 3/2 | no error | 5,024,492 |
| `ft.cfg` | FALSE | 3/2 | no error | 17,317,858 |
| `gil_live.cfg` | FALSE | 2/2 | no error, `Termination` holds | 608,469 |
| `ft_live.cfg` | FALSE | 2/2 | no error, `Termination` holds | 1,953,411 |
| `gil.cfg` | FALSE | 3/3 | no error | 8,164,466 |
| `ft.cfg` | FALSE | 3/3 | no error | 31,688,598 |
| `gil_pyd.cfg` (with `o1`) | TRUE | 3/3 | **deadlock** | |
| `gil_pyd.cfg`, `ft_pyd.cfg` | TRUE | 3/2 | **deadlock** | |

So the protocol of f134da0 is free of deadlocks when no Python code runs
under D, but such code (the comparison and the hash of Python objects, and
the Python API in `run_ocaml`) deadlocks it. The deadlock of `gil_pyd`
(17 steps) goes through a stop-the-world of OCaml:

1. `p1` is in `run_ocaml` (with G and D1, not L) and runs Python code
   directly, such as the `__eq__` of a comparison. That code gives up G
   because `p2` waits for it.
2. The domain `o2` enters `run_python` (L, G, D2) and starts a minor
   collection.
3. The collection waits for `p1` to reach a safepoint, while `p1` waits
   for G, held by `o2`.

Another thread waiting for the GIL is enough to make Python code give up
G. The tests of pyml (`threads-deadlock-repro`, 46488de) reproduce it.

The mutants of 83a65aa (with its `gil.cfg`): M1, the leave hook of the
blocking section takes D before G, found by the assertion of `attach`; M2,
`lock_world_holding_gil` waits for L while holding G, found as a deadlock;
M3, `Py.Thread.call` keeps D during the call, found by the assertion of
`attach`.

## Validation against executions

The model is checked against traces of executions of pyml: with
`PYML_THREADS_TRACE=<file>` (branch `threads-trace` of pyml), each step of
the model that pyml takes is written to `<file>`, named after the labels of
the model (`trace_step` in `pyml_stubs.c`). The steps that take a lock are
written after the lock is taken, and the others (which release one lock)
before it is released, with a global sequence number: the trace orders the
acquisitions and releases of each lock as they happened.

`PymlTrace.tla` accepts a trace if a behavior of the model takes its steps
in its order, each one by its thread, from its label to its next label, so
that the guard of the step holds (the lock that it takes is free). Between
them, the model takes the steps that pyml does not see: the switches of the
GIL by CPython, the blocking sections and the ticks of OCaml, the
registration of a thread in the OCaml runtime, Python code under D, the
start and the end of the threads, the calls and returns of the procedures.
The collections are left out (they only make the other steps wait). The
bounds of the model are lifted, and the counters are left out of the view.
To keep the search small, the next step of the trace is taken as soon as it
can be; otherwise, the silent steps of its thread, and otherwise the silent
steps of the other threads that release a lock, end a detour or take no
lock. These priorities only remove behaviors: an accepted trace is a
behavior of the model, and the rejected traces are checked by hand.

`trace_to_tla.py` writes the trace as a TLA+ module, with the threads
(the main thread, the Python threads, and the OCaml threads with their
domains) and a configuration. A failure of `pthread_mutex_trylock` on L is
written by a thread that holds no lock: if L is free at the failure in the
order of the trace, the release of L that precedes it is moved after it
(the thread that released L had not released it yet), or the failure is
moved after the next acquisition of L (that thread had not written it yet).

The traces come from the stress scenarios of ocip (`tests/threads_stress.py`
of ocip, branch `pyml-fix-deadlock`, with small sizes: `make_small_stress.py`):
Python threads that call OCaml, OCaml domains and systhreads that call
Python, which calls OCaml again, an OCaml mutex shared by Python threads and
domains, a busy wait in OCaml for a Python thread, comparisons and hashes of
Python objects in OCaml, and OCaml code that uses pyml.

```bash
python3 tla/make_small_stress.py <ocip>/tests/threads_stress.py stress_small.py
PYML_THREADS_TRACE=mutex.log python stress_small.py mutex  # with ocip built against this pyml
TLA2TOOLS=$PWD/tla2tools.jar tla/validate_trace.sh mutex.log [--free-threaded]
```

Results (Python 3.14 and 3.14t, OCaml 5.3): the 22 traces (11 scenarios,
with the GIL and free-threaded) are accepted, from 108 to 5,849 steps and up
to 13 threads (5 Python threads and 8 OCaml threads in 8 domains), in less
than 20 seconds each. Three perturbations of a trace (`python_threads`)
are rejected at the step perturbed: a thread takes L while another holds
it, a thread takes D while another holds it, and a `restore` without its
`release`.

The first traces were rejected, and the model was refined accordingly:

- The model released two locks in one step (`run_ocaml`: G and L;
  `unacquire`: G and L; `leave_to_python`, `Py.Thread.call` and
  `pyml_thread_leave`: D and L). In a trace with free-threaded Python, a
  thread attached its thread state after the `unacquire` of another
  thread, and its trylock on L failed: L was not released yet. Each release
  is now a step.
- The model did not have the ticks of the systhreads: a thread in
  `STATE_ALL` yielded D (keeping L and G) to a Python thread that
  registered in the OCaml runtime, or to a thread in `run_ocaml` that
  returned. `AllCode` now yields D (in `STATE_OCAML`, the blocking sections
  already release D the same way).

## Running

```bash
# tla2tools.jar from https://github.com/tlaplus/tlaplus/releases
# (the results above: TLA+ Tools 2.0, nightly of 2026-11-06)
java -cp tla2tools.jar pcal.trans -nocfg tla/PymlThreads.tla  # after editing the algorithm
TLA2TOOLS=$PWD/tla2tools.jar tla/run.sh gil
```

The runs take up to 4 GB of heap.

## Limits

- The model is written by hand from pyml's code, not extracted from it.
  The tests could check traces of the locks against it.
- Not modeled:
  - the queue of deferred decrefs;
  - the `RuntimeError` when the comparison or hash of Python objects calls
    OCaml (`custom_op_depth`), and the `Failure` of the Python API in
    `run_ocaml` (the model never uses it there);
  - the thread states that `PyGILState_Ensure` creates for the OCaml
    threads in `run_python` (the model names each thread state after its
    thread);
  - the unregistration of threads on exit;
  - Python code holding D without releasing G (it does not change the
    locks).
- The bounds (`MaxOps`, `MaxDepth`, the number of threads) are small: the
  results hold for these instances only (see "Configurations" for why
  `MaxDepth` is 3 and 4).
