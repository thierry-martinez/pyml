#!/bin/sh
# tla/validate_trace.sh <trace> [--free-threaded]: checks a trace written by
# pyml (PYML_THREADS_TRACE=<trace>) against PymlTrace.tla, in a temporary
# directory; prints ACCEPTED or REJECTED (with the longest prefix of the
# trace that the model takes). TLA2TOOLS is the path of tla2tools.jar,
# ./tla2tools.jar by default; TLC_HEAP the heap of TLC (2g by default).
set -e
tla="$(cd "$(dirname "$0")" && pwd)"
jar="${TLA2TOOLS:-tla2tools.jar}"
dir="$(mktemp -d)"
cp "$tla/PymlThreads.tla" "$tla/PymlTrace.tla" "$dir"
python3 "$tla/trace_to_tla.py" "$1" "$dir" ${2:+"$2"}
(cd "$dir" && java -Xmx"${TLC_HEAP:-2g}" -XX:+UseParallelGC -cp "$jar" \
   tlc2.TLC -workers auto -config PymlTrace.cfg -metadir states \
   PymlTrace.tla > out 2>&1) || true
if grep -q 'Invariant TraceNotAccepted is violated' "$dir/out"; then
  echo ACCEPTED
elif grep -q 'No error has been found' "$dir/out"; then
  echo "REJECTED after step $(grep -o '"prefix", [0-9]*' "$dir/out" \
    | awk '{print $2}' | sort -n | tail -1) (see $dir)"
  exit 1
else
  echo "ERROR (see $dir/out)"
  exit 2
fi
rm -rf "$dir"
