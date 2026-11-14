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
  lock acquisition:
  - `PyCode` is Python code. It calls OCaml with
    `pyml_threads_enter_from_python`/`leave_to_python`, switches the GIL at
    the eval breaker, and can start a Python stop-the-world.
  - `AllCode` is `STATE_ALL`: the OCaml code called by Python, which holds
    L, G and D and uses the Python API (for ocip, its conversions and
    lookups). It does `Py.Thread.run_ocaml` (`release`/`restore`),
    `Py.Thread.call` and minor collections.
  - `OCamlCode` is the OCaml code in `run_ocaml` (`STATE_OCAML`) or in
    OCaml threads (`STATE_UNKNOWN`). It holds D only. It does blocking
    sections, `Py.Thread.run_python` (`acquire`/`unacquire`) and minor
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

## Results (TLA+ Tools 2.0, nightly of 2026-11-06, 4 cores unless noted)

| Config | Result | Distinct states | Time |
|---|---|---|---|
| `gil.cfg` | no error | 9,029,348 | 1 min 35 s |
| `ft.cfg` | no error | 23,128,960 | 4 min 36 s |
| `gil_deep.cfg` | no error | 1,285,751 | 13 s |
| `ft_deep.cfg` | no error | 2,601,975 | 26 s |
| `gil_live.cfg` | no error, `Termination` holds | 9,029,348 | 7 min 28 s (20 cores) |
| `ft_live.cfg` | no error, `Termination` holds | 23,128,960 | 22 min 47 s (20 cores) |

The variable `saved` is determined by the call stack of each thread (it
is set by `release` and emptied by `restore` of the same call), so it does
not change the reachable states: the safety configs have the same number
of distinct states with and without it, and so do the liveness configs.
The two liveness configs ran at the same time, on 20 cores; without
`saved` (ocip's 3c63b47), on 4 cores, they took 16 and 41 min.

Mutants check that the model is not vacuous. Each is a copy of the spec
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
the assertion of `restore` after 74,818 states (`ft_deep.cfg`: after 209,880 states),
with a trace of 23 steps where only `p1` runs: it calls OCaml, which enters
`run_ocaml` and calls `run_python`, whose OCaml code enters `run_ocaml`
again; the inner `restore` empties the slot, and the outer one restores
NULL. This is the crash of ocip's `test_raise_from_python` (an OCaml
callback raises an OCaml exception, which ocip builds by calling OCaml).
`gil.cfg` (`MaxDepth = 3`) does not find it (9,029,348 states, no error):
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

## Running

```bash
# tla2tools.jar from https://github.com/tlaplus/tlaplus/releases
# (the results above: TLA+ Tools 2.0, nightly of 2026-11-06)
java -cp tla2tools.jar pcal.trans -nocfg tla/PymlThreads.tla  # after editing the algorithm
TLA2TOOLS=$PWD/tla2tools.jar tla/run.sh gil
```

The runs take up to 4 GB of heap (`ft_live`: 7 GB).

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
  - the tick thread of systhreads (OCaml threads yield D at safepoints);
  - Python code holding D without releasing G (it does not change the
    locks).
- The bounds (`MaxOps`, `MaxDepth`, the number of threads) are small: the
  results hold for these instances only (see "Configurations" for why
  `MaxDepth` is 3 and 4).
