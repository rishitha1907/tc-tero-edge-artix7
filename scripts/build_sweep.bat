@echo off
REM build_sweep.bat -- builds every bitstream needed for Table I and Fig. 7.
REM Run from the project root in a "Vivado 2024.2 Tcl Shell" / cmd where vivado is on PATH:
REM     scripts\build_sweep.bat
REM Each build takes ~3-6 minutes. Bitstreams land in build\<name>\.
for %%T in (0 1 2) do (
  for %%X in (4 8) do (
    for %%Y in (16 32 48 64 80) do (
      call vivado -mode batch -nojournal -nolog -source scripts/build.tcl -tclargs %%T %%X %%Y
    )
  )
)
