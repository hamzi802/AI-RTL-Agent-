#!/usr/bin/env bash
# runs tb_sync_fifo on one RTL file
# Usage: scripts/run_tb.sh <rtl.sv> [DATA_WIDTH] [DEPTH] [extra plusargs, e.g. +SEED=7 +DUMP]
# exit 0 pass, 1 fail, 2 compile error
set -u
RTL=${1:?usage: run_tb.sh <rtl.sv> [DATA_WIDTH] [DEPTH] [plusargs...]}
W=${2:-8}; D=${3:-16}; shift $(( $# < 3 ? $# : 3 ))
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d)
if ! iverilog -g2012 -Wall -s tb_sync_fifo -P tb_sync_fifo.DATA_WIDTH="$W" -P tb_sync_fifo.DEPTH="$D" \
       -o "$OUT/sim" "$ROOT/tb/tb_sync_fifo.sv" "$RTL" 2> "$OUT/compile.log"; then
  cat "$OUT/compile.log"
  echo "TEST_RESULT: FAIL reason=compile_error"
  exit 2
fi
vvp -n "$OUT/sim" "$@" | tee "$OUT/sim.log" | grep -v '\$finish called'
tail -n 3 "$OUT/sim.log" | grep -q "TEST_RESULT: PASS"
