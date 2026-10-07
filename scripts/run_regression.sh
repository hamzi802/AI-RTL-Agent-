#!/usr/bin/env bash
# check the TB: ref FIFO should pass every config, every mutant should fail
cd "$(dirname "$0")/.."
fail=0
echo "== rtl/reference (expect PASS) =="
for cfg in "8 16" "8 2" "1 4" "32 8" "40 64"; do
  for seed in 1 42 1234; do
    set -- $cfg
    res=$(scripts/run_tb.sh rtl/reference/sync_fifo.sv $1 $2 +SEED=$seed | tail -n1)
    printf "  W=%-3s D=%-3s seed=%-5s %s\n" $1 $2 $seed "$res"
    [[ $res == "TEST_RESULT: PASS"* ]] || fail=1
  done
done
echo "== Mutants (expect FAIL) =="
for m in tb/sanity/mutants/*.sv; do
  out=$(scripts/run_tb.sh "$m" 8 16)
  res=$(echo "$out" | tail -n1)
  first=$(echo "$out" | grep -m1 '^ERROR' | cut -c1-110)
  printf "  %-24s %s\n      first: %s\n" "$(basename "$m" .sv)" "${res%% tests=*}" "$first"
  [[ $res == "TEST_RESULT: FAIL"* ]] || { echo "  !! mutant escaped"; fail=1; }
done
[[ $fail == 0 ]] && echo "REGRESSION: OK" || echo "REGRESSION: PROBLEM"
exit $fail
