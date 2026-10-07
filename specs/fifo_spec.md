# sync_fifo spec

Owner: Rumali

This is the spec the agent gets as input, and it's also what tb/tb_sync_fifo.sv checks against. If we change anything here after freezing, bump the rev and update the TB in the same commit.

## Overview

Single clock FIFO, parameterized width and depth. All state changes on posedge clk.

## Parameters

- `DATA_WIDTH` (default 8): any value >= 1
- `DEPTH` (default 16): power of 2, >= 2

So ADDR_W = $clog2(DEPTH) and the count is $clog2(DEPTH)+1 bits wide (it has to hold DEPTH itself).

## Interface

```systemverilog
module sync_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,    // sync, active low
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  count
);
```

Names, widths and directions are fixed, no extra ports.

## Clock

One clock, `clk`. Everything is on the rising edge. No negedge logic, no gated clocks.

## Reset

rst_n is synchronous, active low. On a posedge with rst_n = 0:

- count = 0, empty = 1, full = 0
- rd_data = 0
- read and write pointers go to 0
- wr_en / rd_en are ignored in that cycle

The memory array itself doesn't need to be cleared. No output should be X after the first reset edge.

## Write

A write happens on a posedge if wr_en = 1 and full = 0. wr_data goes to the tail of the queue.
If wr_en = 1 while full = 1, the write is dropped. Nothing gets overwritten.

## Read

A read happens on a posedge if rd_en = 1 and empty = 0. The oldest entry is popped and loaded into rd_data, so rd_data has the new value right after that edge (1 cycle latency, not FWFT).

If no read happens (rd_en = 0, or rd_en = 1 while empty), rd_data keeps its old value.

## Read and write on the same edge

full/empty are the values before the edge. Each request is handled by the rules above:

- empty: write goes in, read is ignored -> count = 1, rd_data unchanged
- full: read happens, write is ignored -> count = DEPTH-1
- anything else: both happen -> count unchanged

## Overflow / underflow

- Overflow (wr_en while full): write is dropped, stored data and count don't change.
- Underflow (rd_en while empty): read is ignored, rd_data keeps its old value, count stays 0 (doesn't wrap).
- There are no error flag outputs for these in this version.

## Flags

- full = (count == DEPTH)
- empty = (count == 0)

   full, empty, count and rd_data must depend only on registered state: no combinational path from wr_en, rd_en or wr_data to any output. Decoding a register is fine (e.g. full = (count == DEPTH)); each output doesn't have to be its own flop.

## Example (DEPTH = 4)

```
edge  inputs before edge     count empty full rd_data
 0    rst_n=0                  0     1    0     0
 1    wr_en=1 wr_data=A        1     0    0     0
 2    wr_en=1 wr_data=B        2     0    0     0
 3    rd_en=1                  1     0    0     A
 4    idle                     1     0    0     A
 5    rd_en=1                  0     1    0     B
 6    rd_en=1 (empty)          0     1    0     B
```

## Not in this version

Async/dual clock, non power of 2 depth, FWFT mode, almost_full/almost_empty, overflow/underflow outputs. Possible phase 2 items.

## RTL rules

- Synthesizable SV, has to compile with Icarus 12 (`iverilog -g2012`)
- One file, module name `sync_fifo`
- No initial blocks, no # delays, no vendor primitives
- Should also go through yosys `read_verilog -sv; synth` (we'll check this in phase 2)
