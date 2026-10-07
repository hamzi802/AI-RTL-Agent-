# sync_fifo test plan

Owner: Rumali

## Approach

The TB only knows the spec, it doesn't look inside the DUT, so we can use it on whatever the agent generates.

There's a small reference model inside the TB that predicts count/full/empty/rd_data every cycle. Inputs change on negedge. Outputs are compared in two places:

1. just after posedge, to check the new state
2. just after the inputs change at negedge, to catch outputs that depend combinationally on wr_en/rd_en/wr_data

All compares use `!==` so X/Z on an output counts as a failure.

## Tests

| test | spec section | checks |
|---|---|---|
| reset_values | Reset | outputs after reset |
| single_write_read | Write, Read | basic write, 1 cycle read latency, rd_data holds |
| fill_to_full_patterns | Write, Flags | full at exactly DEPTH, 0/1/alternating/walking-1 data |
| overflow_attempt | Write | writes when full are dropped |
| drain_to_empty | Read | order is preserved, empty at exactly 0 |
| underflow_attempt | Read | reads when empty ignored, count doesn't wrap |
| simultaneous_rw_when_empty | Same edge | write in, read ignored |
| simultaneous_rw_when_full | Same edge | read out, write ignored |
| simultaneous_rw_mid | Same edge | both happen, count stays |
| pointer_wraparound | Write, Read | pointers wrap many times |
| reset_mid_operation | Reset | reset beats wr_en/rd_en, no stale data afterwards |
| idle_hold | Read, Flags | nothing changes when idle |
| constrained_random | all | 5000 cycles by default, write heavy / read heavy / balanced phases, ~1% resets |

## Coverage

The run fails if any of these never happened, so a "pass" actually means the corners were exercised:
full, empty after holding data, overflow attempt, underflow attempt, rd+wr while empty, rd+wr while full, rd+wr in between, write pointer wrap, reset while holding data.

## Configs

W/D = 8/16 (default), 8/2 (smallest depth), 1/4, 32/8, 40/64 (wider than 32 bits). Seeds 1, 42, 1234 for each.

## Checking the TB itself

To make sure the TB actually catches bugs I made 8 broken copies of a simple FIFO in tb/sanity/mutants. The good one has to pass on all configs and every broken one has to fail. `scripts/run_regression.sh` does both.

- m1: full goes high one entry early
- m2: writes accepted when full
- m3: reads accepted when empty
- m4: count uses if/else, wrong on simultaneous rd+wr
- m5: rd_data not reset
- m6: empty depends on wr_en combinationally
- m7: rd_data cleared instead of held
- m8: write pointer not reset

We can also use these for the demo: give the agent one of them and show it fixing the bug from the TB errors.

## Output format

Each mismatch prints one line, and the last line is always the result:

```
ERROR test=<name> cycle=<n> phase=<post-edge|comb> signal=<sig> expected=0x.. got=0x.. | inputs: ... | model: count=<n>
TEST_RESULT: PASS ...   (or FAIL)
```

run_tb.sh returns 0 for pass, 1 for fail, 2 if it doesn't compile. Only the first 25 ERROR lines are printed (+MAX_ERR_PRINT=n to change it) so we don't flood the LLM context.
