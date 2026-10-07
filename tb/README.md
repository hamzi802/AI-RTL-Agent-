# tb

Run the TB on a FIFO (default DATA_WIDTH=8, DEPTH=16):

    scripts/run_tb.sh rtl/reference/sync_fifo.sv
    scripts/run_tb.sh rtl/generated/sync_fifo.sv 32 8 +SEED=7 +DUMP

Check the TB itself (good FIFO passes, all broken ones fail):

    scripts/run_regression.sh

Needs Icarus 12 (`sudo apt install iverilog`). tb/sanity/mutants are broken copies of the reference FIFO, only used to check that the TB catches bugs.
