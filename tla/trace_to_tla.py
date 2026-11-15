"""
Convert a trace of pyml (PYML_THREADS_TRACE) into TraceData.tla and a TLC
configuration for PymlTrace.tla.

Usage: python3 trace_to_tla.py <trace> <output directory> [--free-threaded]
"""

import sys
from pathlib import Path


# The steps that take L, and those that release it.
TAKE_L = {("py_lockL", "py_d"), ("py_waitL", "py_g"),
          ("all_restore_L", "all_restore_g"), ("all_call_back", "all_call_d"),
          ("all_call_L", "all_call_g"), ("oc_rp_L1", "oc_rp_g1"),
          ("oc_rp_L2", "oc_rp_g2")}
RELEASE_L = {("py_leave_L", "py"), ("all_run_L", "all_run"),
             ("all_call_unlock", "all_call"), ("oc_rp_unlock1", "oc"),
             ("oc_rp_unlock2", "oc"), ("p_unlock", "p_run")}
# The failures of pthread_mutex_trylock on L.
TRYLOCK_FAILED = {("py_lockL", "py_waitL"), ("all_call_back", "all_call_L")}


def order_failed_trylocks(events: list) -> tuple[list, int]:
    """
    Order the failures of trylock on L while L is held.

    The steps that take L are written after L is taken, and the steps that
    release L (which only release L) before L is released: the trace orders
    the acquisitions and releases of L as they happened. A failure of
    trylock is written by a thread that holds no lock: if L is free at the
    failure in the order of the trace, the thread that held L had either
    written its release but not released L yet, or taken L but not written
    it yet. In the first case (the thread that released L wrote nothing
    since), the release is moved after the failure; otherwise, the failure
    is moved after the next acquisition of L (before which the failing
    thread writes nothing: its next step takes L).
    """
    result: list = []
    pending: list = []  # failures waiting for the next acquisition
    holder = "main"  # the main thread starts with L
    last_release = None  # the index in result of the last release of L
    moved = 0
    for event in events:
        _, tid, label, next_label, _ = event
        step = (label, next_label)
        if step in TRYLOCK_FAILED and holder is None:
            moved += 1
            if last_release is not None:
                release = result[last_release]
                if all(e[1] != release[1] for e in result[last_release + 1:]):
                    del result[last_release]
                    result.append(event)
                    result.append(release)
                    last_release = len(result) - 1
                    continue
            pending.append(event)
            continue
        if any(p[1] == tid for p in pending):
            sys.exit(f"thread {tid} steps before its failure of trylock is placed")
        result.append(event)
        if step in TAKE_L:
            holder = tid
            result.extend(pending)
            pending = []
        elif step in RELEASE_L:
            holder = None
            last_release = len(result) - 1
    if pending:
        sys.exit("failures of trylock with no acquisition of L after them")
    return result, moved


def main() -> None:
    trace, out = Path(sys.argv[1]), Path(sys.argv[2])
    free_threaded = "--free-threaded" in sys.argv[3:]
    events = []
    for line in trace.read_text().splitlines():
        seq, tid, label, next_label, domain = line.split()
        events.append((int(seq), tid, label, next_label, int(domain)))
    events.sort()
    events, moved = order_failed_trylocks(events)
    # Each thread is a Python thread (the main thread, "p_start", or a
    # thread whose first step is a call of OCaml by Python, "py") or an OCaml
    # thread (its first step is Py.Thread.run_python, "oc").
    kinds: dict[str, str] = {}
    domains: dict[str, int] = {}
    main_thread = None
    for _, tid, label, _, domain in events:
        if tid not in kinds:
            if label == "p_start":
                kinds[tid], main_thread = "p", tid
            elif label == "py":
                kinds[tid] = "p"
            elif label == "oc":
                kinds[tid] = "o"
            else:
                sys.exit(f"thread {tid}: unexpected first step {label}")
        if domain >= 0:
            domains.setdefault(tid, domain + 1)
    if main_thread is None:
        sys.exit("no main thread (p_start)")
    name = {tid: f"{kind}{tid}" for tid, kind in kinds.items()}
    for tid, kind in kinds.items():
        if kind == "p" and domains.get(tid, 1) != 1:
            sys.exit(f"Python thread {tid} in domain {domains[tid]}")
    ocaml = [t for t, k in kinds.items() if k == "o"]
    python = [t for t, k in kinds.items() if k == "p"]
    all_domains = sorted({1} | {domains.get(t, 1) for t in ocaml})

    def tla_set(threads: list[str]) -> str:
        return "{" + ", ".join(f'"{name[t]}"' for t in threads) + "}"

    records = ",\n  ".join(
        f'[t |-> "{name[tid]}", from |-> "{label}", to |-> "{next_label}"]'
        for _, tid, label, next_label, _ in events
    )
    odom = " [] ".join(f'(t = "{name[th]}") -> {domains.get(th, 1)}'
                       for th in ocaml) or "OTHER -> 1"
    if ocaml:
        odom = f"CASE {odom} [] OTHER -> 1"
    else:
        odom = "1"
    first = {}
    for index, (_, tid, _, _, _) in enumerate(events, start=1):
        first.setdefault(tid, index)
    first_cases = " [] ".join(f'(t = "{name[t]}") -> {k}' for t, k in first.items())
    (out / "TraceData.tla").write_text(f"""---- MODULE TraceData ----
EXTENDS Sequences
TPyThreads == {tla_set(python)}
TOCamlThreads == {tla_set(ocaml)}
TP1 == "{name[main_thread]}"
TFirst == [t \\in {tla_set(python + ocaml)} |-> CASE {first_cases}]
TDomains == {{{", ".join(map(str, all_domains))}}}
TODom(t) == {odom}
TraceSeq == <<
  {records}
>>
====
""")
    (out / "PymlTrace.cfg").write_text(f"""SPECIFICATION TraceSpec
CONSTANTS
  PyThreads <- TPyThreads
  OCamlThreads <- TOCamlThreads
  P1 <- TP1
  Domains <- TDomains
  ODom <- TODom
  FreeThreaded = {"TRUE" if free_threaded else "FALSE"}
  PythonUnderD = TRUE
  PerThreadSlot = FALSE
  MaxOps = 1
  MaxDepth = 1
  None = None
  CanDo <- Unbounded
  CanNest <- Unbounded
VIEW TraceView
INVARIANT Progress
INVARIANT TraceNotAccepted
CHECK_DEADLOCK FALSE
""")
    print(f"{len(events)} steps ({moved} failures of trylock moved), "
          f"Python threads {len(python)}, "
          f"OCaml threads {len(ocaml)}, domains {all_domains}")


main()
