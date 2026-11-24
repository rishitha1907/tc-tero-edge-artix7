#!/bin/bash
# build_sweep.sh -- Linux version of build_sweep.bat (run from the project root)
for T in 0 1 2; do for X in 4 8; do for Y in 16 32 48 64 80; do
  vivado -mode batch -nojournal -nolog -source scripts/build.tcl -tclargs $T $X $Y
done; done; done
