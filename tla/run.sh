#!/bin/sh
# tla/run.sh <config>: runs TLC on MC.tla with tla/<config>.cfg (gil, ft,
# gil_live, ft_live, gil_deep, ft_deep); the output is written to
# tla/<config>.out.
# TLA2TOOLS is the path of tla2tools.jar
# (https://github.com/tlaplus/tlaplus/releases), ./tla2tools.jar by default.
set -e
cd "$(dirname "$0")"
jar="${TLA2TOOLS:-tla2tools.jar}"
java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto \
  -config "$1.cfg" -metadir "states/$1" MC.tla > "$1.out" 2>&1 || true
grep -E 'No error|^Error:|violated|Deadlock reached|distinct states found' \
  "$1.out" | head -4
