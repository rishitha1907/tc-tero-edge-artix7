# TC-TERO TRNG on the EDGE Artix-7

A Verilog implementation of a configurable Transition Effect Ring Oscillator (TERO) true random number generator (TRNG) for the EDGE Artix-7 FPGA board. The repository includes plain TERO, C-TERO, and TC-TERO ring designs; a controller and UART host interface; Vivado scripts; Python collection and analysis tools; and instructions for repeating selected experiments from the FPL 2020 paper *On the Feasibility of TERO-based TRNG on Xilinx FPGAs*.

The design targets the EDGE Artix-7 board with an XC7A35T-1FTG256C FPGA. The intended toolchain is Vivado 2024.2 and Python 3.10 or newer.

> **Reproduction note:** TERO behavior depends on the FPGA device, placement, and operating conditions. A result from one board or run is not guaranteed to match the paper or another board.

## Contents

- [Project status and measured results](#project-status-and-measured-results)
- [Repository contents](#repository-contents)
- [Requirements](#requirements)
- [Setup the board and PC](#setup-the-board-and-pc)
- [Simulate the design](#simulate-the-design)
- [Build the bitstream](#build-the-bitstream)
- [Program the board and check the link](#program-the-board-and-check-the-link)
- [Run the experiments](#run-the-experiments)
- [NIST SP 800-22 optional test](#nist-sp-800-22-optional-test)
- [Troubleshooting](#troubleshooting)
- [Generated files and GitHub](#generated-files-and-github)
- [Paper reference and acknowledgements](#paper-reference-and-acknowledgements)

## Project status and measured results

The accompanying report documents one EDGE Artix-7 board and one placement origin, X4Y16. It records a TC-TERO parameter search over 196,608 values, counter and random-bit collection, AIS-31 testing, and area/timing inspection.

| Measurement | Paper reference | Reported EDGE run |
|---|---:|---:|
| Usable TC-TERO parameters | 5.18% average | 4.77% of 196,608 values |
| AIS-31 Procedure B, raw bits | Pass | Pass |
| AIS-31 Procedure A, raw bits | Pass | Pass after 4-bit LFSR |
| AIS-31 Procedure A after 4-bit LFSR XOR | Pass | Pass |
| Entropy estimate (AIS-31 T8) | 0.9993 bit/bit | 0.9991 bit/bit on the Procedure B run |
| TC-TERO ring area | 21 LUTs in this design | 21 LUTs and 10 F7MUXes |
| Whole TRNG hierarchy | 40 LUTs / 29 FFs | 118 LUTs / 48 FFs in the reported build |
| Throughput | 1.912 Mbit/s | 1.32 Mbit/s |

The report selected parameter `0x334af`. Its measurements changed between search, probe, and later counter runs: the later 65,536-count collection had mean 140.9 and standard deviation 16.8, with no saturated counts. The report discusses sensitivity to operating conditions as a likely cause. Treat the numbers as a record of that run, not as a stable guarantee. The report's figure caption rounds the usable fraction to 4.79%; its results table and main text report 4.77% (9,369 / 196,608).

The report explicitly says these items were not completed in that run:

- The 10-origin plain-TERO Table I sweep.
- The C-TERO versus TC-TERO comparison across origins and boards.
- NIST SP 800-22 testing.
- Testing multiple boards or multiple placement origins.

The RTL compiled in XSim, but behavioral simulation could not be elaborated on the report author's laptop because Windows Code Integrity blocked `xelab.exe`. Ping and counter-mode checks were confirmed on hardware. Do not mark the simulation or experiments above as passing until you have run and recorded them yourself.

See [`docs/report.pdf`](docs/report.pdf) for the detailed method, observations, and limitations. Add run-specific measurements to [`docs/results.md`](docs/results.md) as you collect them.

## Repository contents

```text
.
├── rtl/
│   ├── tero_top.v
│   ├── tero_rng.v
│   ├── tero_loop_sel.v
│   ├── tero_loop.v
│   ├── c_tero_loop.v
│   ├── tc_tero_loop.v
│   ├── host_ctrl.v
│   └── uart.v
├── constr/
│   ├── edge_a7_tero.xdc
│   └── pblock_origin.xdc
├── scripts/
│   ├── create_project.tcl
│   ├── pre_bitstream.tcl
│   ├── build.tcl
│   ├── build_sweep.bat
│   └── build_sweep.sh
├── sim/
│   └── tb_top.v
├── host/
│   ├── tero_host.py
│   ├── analyze_search.py
│   ├── analyze_counter.py
│   ├── ais31.py
│   └── postproc_lfsr.py
├── docs/
│   ├── report.pdf
│   ├── results.md
│   └── screenshots/
├── requirements.txt
├── .gitignore
└── README.md
```

### RTL source

| File | Purpose |
|---|---|
| `rtl/tero_top.v` | Top-level design: clock generation, reset, UART, FIFO, and LEDs. |
| `rtl/tero_rng.v` | TERO controller and oscillation counter; includes precharge, end detection, and timeout handling. |
| `rtl/tero_loop_sel.v` | Selects plain TERO, C-TERO, TC-TERO, or the simulation model. |
| `rtl/tero_loop.v` | Plain TERO ring oscillator (paper Fig. 2 / Table I). |
| `rtl/c_tero_loop.v` | C-TERO ring oscillator with a 16-bit path-selection parameter. |
| `rtl/tc_tero_loop.v` | TC-TERO ring oscillator with a 20-bit path-selection parameter. |
| `rtl/host_ctrl.v` | PC command interface for ping, parameter search, counter collection, and TRNG modes. |
| `rtl/uart.v` | UART transmit/receive logic and FIFO. |

### Constraints, scripts, simulation, and host tools

| Path | Purpose |
|---|---|
| `constr/edge_a7_tero.xdc` | Board pin assignments, clocks, and intentional combinational-loop handling. |
| `constr/pblock_origin.xdc` | Fixed placement region for the ring; default origin is X4Y16. |
| `scripts/create_project.tcl` | Creates the Vivado project, adds RTL and constraints, and sets project options. |
| `scripts/pre_bitstream.tcl` | Sets the intended loop DRC handling before bitstream generation. |
| `scripts/build.tcl` | Batch build for a chosen loop type and placement origin. |
| `scripts/build_sweep.bat`, `scripts/build_sweep.sh` | Build bitstreams for a set of placement origins. |
| `sim/tb_top.v` | Testbench intended to check ping, counter, packed TRNG bits, and search records. |
| `host/tero_host.py` | Sends commands to the board and collects parameter-search, counter, probe, or TRNG data. |
| `host/analyze_search.py` | Analyzes parameter-search records; reports usable parameters and creates Fig. 7-style plots. |
| `host/analyze_counter.py` | Summarizes counter records and creates Fig. 8-style plots and a stochastic-model fit. |
| `host/ais31.py` | Runs AIS-31 Procedures A and B. |
| `host/postproc_lfsr.py` | Applies the 4-bit LFSR XOR post-processing used before the reported NIST/AIS-31 follow-up. |

## Requirements

### Hardware

- EDGE Artix-7 board with FPGA `XC7A35T-1FTG256C`.
- USB A-to-B cable connected to the board's USB JTAG port (this connection also supplies USB-UART).
- Vivado-supported cable drivers.

### Software

- Xilinx Vivado 2024.2.
- Python 3.10 or newer.
- Python packages: `pyserial`, `numpy`, `scipy`, and `matplotlib`.
- Optional NIST test: NIST Statistical Test Suite (STS) 2.1.2; Windows users can run it under WSL/Ubuntu.

From the repository root, install the host packages:

```bash
python -m pip install -r requirements.txt
```

The `requirements.txt` file should list `pyserial`, `numpy`, `scipy`, and `matplotlib`.

## Setup the board and PC

1. Install Python 3.10+ and Vivado 2024.2. During Vivado installation, include the cable drivers.
2. Unzip or clone this repository to a path without spaces, for example `C:\tc_tero_edge`.
3. Set the board power switch SW2 to USB.
4. Connect the USB Type-B cable to port U9, labeled **USB JTAG**. This single cable provides power, JTAG programming, and UART. No other wiring is needed for this design; remove unrelated sensors or jumper wires.
5. Confirm the board's D2 power LED is lit.
6. In Windows Device Manager, open **Ports (COM & LPT)** and note the **USB Serial Port (COMn)** number. Substitute this for `COM5` in the examples below. On Linux, the serial device may be `/dev/ttyUSB1`.

If Vivado cannot find the board, reinstall the cable drivers. On Windows, the Vivado driver installer is commonly located under `C:\Xilinx\Vivado\2024.2\data\xicom\cable_drivers\nt64`; the report includes the driver-wrapper command used on its machine.

## Simulate the design

Simulation is recommended before hardware use when the installed Vivado environment supports it:

1. Open Vivado 2024.2 and its Tcl Console.
2. Create the project:

   ```tcl
   cd C:/tc_tero_edge
   source scripts/create_project.tcl
   ```
3. Select **File > Add Sources > Add or create simulation sources**, add `sim/tb_top.v`, then finish.
4. In the Sources pane, expand **Simulation Sources > sim_1**, right-click `tb_top`, and choose **Set as Top**.
5. Choose **Run Simulation > Run Behavioral Simulation**.
6. When the waveform opens, enter `run all` in the Tcl Console.

A successful testbench run should end with `ALL TESTS PASSED`. The checks are intended to cover ping, counter mode returning 105, TRNG-mode bit packing, and a 4,096-trial search record. In the report's environment, RTL compilation succeeded but behavioral elaboration was blocked by Windows Code Integrity preventing `xelab.exe` from running; hardware checks were used instead.

## Build the bitstream

### Create the project

In the Vivado Tcl Console:

```tcl
cd C:/tc_tero_edge
source scripts/create_project.tcl
```

This script targets `xc7a35tftg256-1`, adds the RTL and XDC files, sets `tero_top` as the top module, selects TC-TERO by default (`LOOP_TYPE=2`), and installs the pre-bitstream hook.

### Build from the Vivado GUI

If creating the project manually:

1. **File > Project > New**. Select **RTL Project** and **Do not specify sources at this time**.
2. Select Artix-7, package `ftg256`, speed `-1`, part `xc7a35tftg256-1`.
3. Add all Verilog files in `rtl/` as design sources.
4. Add `constr/edge_a7_tero.xdc` and `constr/pblock_origin.xdc` as constraints.
5. Set `tero_top` as the top module.
6. In **Tools > Settings > Project Settings > General > Generics/Parameters**, set `LOOP_TYPE` to `2` for TC-TERO.
7. In **Tools > Settings > Project Settings > Bitstream**, set `scripts/pre_bitstream.tcl` as the `tcl.pre` hook.
8. For `pblock_origin.xdc`, keep it enabled for implementation and disable it for synthesis if Vivado presents the source properties.
9. Select **Generate Bitstream** and allow Vivado to run synthesis and implementation.

### Build from the command line

Open the Vivado 2024.2 Tcl Shell and run:

```tcl
cd C:/tc_tero_edge
vivado -mode batch -source scripts/build.tcl -tclargs 2 4 16
```

The arguments are `LOOP_TYPE X Y`: `0` = plain TERO, `1` = C-TERO, `2` = TC-TERO. For example, `2 4 16` builds TC-TERO at origin X4Y16. A build produces a bitstream plus utilization, timing, and DRC reports under the generated build directory. The project flow may also create a Vivado GUI project under `vivado_proj/`.

Expected warnings include the combinational loop (`LUTLP-1`) and timing-loop messages; the oscillator intentionally contains a ring. A package-pin assignment error, any synthesis/implementation error, or a critical warning that a `PACKAGE_PIN` could not be applied is not expected. The report's ring implementation used 21 LUTs and 10 F7MUXes in the 4x5-slice pblock at `SLICE_X4Y16`.

## Program the board and check the link

### Program with Hardware Manager

1. In Vivado, open **Hardware Manager > Open Target > Auto Connect**.
2. Select device `xc7a35t_0` and choose **Program Device**.
3. Select the generated `.bit` file. Leave Debug Probes empty unless you have a matching probes file.
4. Program the FPGA.

Programming over JTAG is lost when board power is removed; flash programming is not required for this workflow.

### Or program through Tcl

Replace the bitstream path with the file generated on your machine:

```tcl
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {C:/tc_tero_edge/build/tc_tero_X4Y16/tero_tc_tero_X4Y16.bit} [get_hw_devices xc7a35t_0]
program_hw_devices [get_hw_devices xc7a35t_0]
```

### Check LEDs and UART

| LED | Meaning |
|---|---|
| D1 (DONE) | FPGA configured. |
| D3 (LED0) | Heartbeat, approximately one blink every 0.7 seconds. |
| D4 (LED1) | MMCM locked; the 100 MHz clock is ready. |
| D5 (LED2) | A command is running. |
| D6 / D8 / D9 | Search / counter / TRNG mode active. |
| D10 / D11 | UART receive / transmit activity. |
| D12-D19 | Last oscillation count in binary; may flicker while running. |

The center push button SW22 resets or aborts a running command. Other buttons and switches are not used by this design.

Check the connection (change `COM5` to your port):

```bash
python host/tero_host.py --port COM5 ping
```

Expected response: `OK: board answered, LOOP_TYPE=2 (TC-TERO (20-bit)), version=1`.

## Run the experiments

Run the Python commands from the `host/` directory, or prefix the script paths with `host/`. Replace the example parameter and serial port with your selected values. Search and raw TRNG collection can take a long time and create large files.

### TC-TERO parameter search (paper Section V.A / Fig. 7)

For a full 20-bit search:

```bash
python tero_host.py --port COM5 search --out search_tc_X4Y16.bin
```

The command runs 4,096 trials per parameter and writes records in chunks. The full `2^20` search takes about 30-60 minutes according to the project notes. Add `--resume` to continue an interrupted search in the same output file.

Analyze the results:

```bash
python analyze_search.py search_tc_X4Y16.bin --target 112 7
```

This reports the distribution, usable-parameter fraction, and candidates closest to mean 112 / standard deviation 7. Write down the selected parameter ID and use it in subsequent commands. The paper's average TC-TERO usable fraction is 5.18%; results on another chip can differ.

The report's completed run searched parameters 65,536 through 262,143 (196,608 values) at X4Y16, yielding 4.77% (9,369) within its criterion. It did not search the entire 20-bit space.

### Counter distribution and stochastic model (paper Section V.B / Fig. 8)

With a candidate parameter, collect 65,536 counts:

```bash
python tero_host.py --port COM5 counter --param 0x334af --n 65536 --out cnt_tc_X4Y16.bin
python analyze_counter.py cnt_tc_X4Y16.bin
```

The analysis reports mean, standard deviation, fitted model parameters `R`, `sigma_r`, and `dr`, and creates a Fig. 8-style histogram/model plot. The report measured parameter `0x334af`; its later counter-mode run had mean 140.9 and standard deviation 16.8. Its fitted `R` was 1.00497, `sigma_r` 0.00424, while `dr` reached the model's limit of 0.5. These later measurements differed from initial search/probe readings, as discussed in the report.

### Generate bits and run AIS-31 (paper Section V.C)

For the paper-scale 1 Gibit collection, request 134,217,728 bytes:

```bash
python tero_host.py --port COM5 trng --param 0x334af --nbytes 134217728 --out trng.bin
```

This takes about 10 minutes according to the notes. The command reports on-chip throughput and the fraction of saturated values discarded. For a shorter demonstration, the report's live demo uses 4,000,000 bytes (32 Mbit):

```bash
python tero_host.py --port COM5 trng --param 0x334af --nbytes 4000000 --out demo_trng.bin
```

Run AIS-31 on raw output:

```bash
python ais31.py AB trng.bin
```

Procedure A or B may fail for a candidate on a particular chip. Try another candidate from the search output and record the parameter used. The report's raw bits passed Procedure B but failed Procedure A, mainly at T1 (monobit).

The paper applies a 4-bit maximal-length LFSR XOR post-processing step before its NIST tests. The project also reruns Procedure A after this step:

```bash
python postproc_lfsr.py trng.bin trng_lfsr.bin
python ais31.py A trng_lfsr.bin
```

The report says Procedure A passed after this post-processing step. It does not report completing NIST SP 800-22.

### Plain TERO placement sweep (paper Section III / Table I)

The paper compares plain TERO at ten origins: X in `{4, 8}` and Y in `{16, 32, 48, 64, 80}`. For each origin, build a plain TERO bitstream (`LOOP_TYPE=0`), program it, then collect and analyze 65,536 counts. Example for X4Y16:

```bash
vivado -mode batch -source scripts/build.tcl -tclargs 0 4 16
python tero_host.py --port COM5 counter --param 0 --n 65536 --out cnt_plain_X4Y16.bin
python analyze_counter.py cnt_plain_X4Y16.bin --no-plot
```

Repeat with the other nine origins and fill a 2x5 table with mean and standard deviation. The finding to check is that most origins produce nearly constant, very small, or saturated counts, while only a few give a usable spread. The project notes say `scripts/build_sweep.bat` can build the set of bitstreams. The report did not complete this sweep.

### Compare C-TERO and TC-TERO (paper Fig. 7)

At each selected origin, build C-TERO with `LOOP_TYPE=1` and search its 16-bit parameter space:

```bash
vivado -mode batch -source scripts/build.tcl -tclargs 1 4 16
python tero_host.py --port COM5 search --bits 16 --out search_c_X4Y16.bin
```

Build and search TC-TERO at the same origin (`LOOP_TYPE=2`). Then compare records with the analysis script:

```bash
python analyze_search.py --fig7 C:X4Y16=search_c_X4Y16.bin TC:X4Y16=search_tc_X4Y16.bin
```

Use matching origins and document the board count and search ranges. The paper reports average extraction rates of 2.62% for C-TERO and 5.18% for TC-TERO across ten origins and three boards. The project notes recommend two to four origins of each type as a smaller initial comparison; ten TC-TERO searches may take 5-10 hours. The report did not complete this comparison.

### Area and throughput (paper Table II)

Use Vivado's hierarchical utilization report or the `util_hier.rpt` from a batch build. Check `u_rng` for the controller/TRNG and `u_rng/u_loop` for the ring. The paper reports 40 LUTs / 29 flip-flops for the whole TRNG and 1.912 Mbit/s. The report measured 118 LUTs / 48 flip-flops for its complete hierarchy, 21 LUTs and 10 F7MUXes for the ring, and 1.32 Mbit/s. The controller size and measured throughput depend on this implementation and run conditions.

## NIST SP 800-22 optional test

The project notes recommend NIST STS 2.1.2 after producing `trng_lfsr.bin`:

1. Obtain STS 2.1.2 from NIST's Random Bit Generation documentation/software page and follow its license and setup terms.
2. On Windows, use WSL/Ubuntu if needed. From the STS source directory:

   ```bash
   make
   ./assess 1000000
   ```

3. In the interactive prompts, select the input file `trng_lfsr.bin`, choose all tests (`1`), keep parameter adjustments at `0`, set the number of bitstreams (the notes use 1,073), and choose binary input format (`1`).
4. If the result directories are missing, run the STS `create-dir-script` from its `experiments/` directory once.
5. Review `experiments/AlgorithmTesting/finalAnalysisReport.txt`.

The notes give these example checks for 1,073 sequences: a test proportion of at least about 0.981 and uniformity P-value of at least 0.0001. Follow the STS documentation for interpretation. NIST testing was not completed for the measurements in the report; do not claim a pass until you run it and archive the output summary.

## Live demonstration sequence

The report's short demonstration checks the programmed board, counter, probe variation, a small search, raw AIS-31, and post-processed Procedure A. Close PuTTY or any other serial-port program first. Change the COM port and parameter as needed.

```bash
cd C:\tc_tero_edge\host
python tero_host.py --port COM5 ping
python tero_host.py --port COM5 counter --param 0x334af --n 65536 --out demo_cnt.bin
python analyze_counter.py demo_cnt.bin
python tero_host.py --port COM5 probe --params 0x334af 0x3fabd 0x1f5be --repeat 2
python analyze_search.py mini2.bin --start 65536 --target 112 7
python tero_host.py --port COM5 trng --param 0x334af --nbytes 4000000 --out demo_trng.bin
python ais31.py AB demo_trng.bin
python postproc_lfsr.py demo_trng.bin demo_trng_lfsr.bin
python ais31.py A demo_trng_lfsr.bin
```

Parameter behavior can drift between runs and operating conditions; small numeric differences are expected. Ensure `mini2.bin` exists before running its analysis command.

## Troubleshooting

| Symptom | Checks and suggested fix |
|---|---|
| `ping` times out and D4 is off | The MMCM may not be locked. Check the selected bitstream, clock pin constraint, and implementation. |
| `ping` times out and D4 is on | Confirm the COM port and close other serial programs such as PuTTY or Arduino IDE. Press SW22 and retry. |
| `ping` returns unreadable characters | Check that the host uses 3,000,000 baud. Try connecting directly to the PC rather than through a USB hub. |
| Bitstream build reports `LUTLP-1` as an error | Check that `scripts/pre_bitstream.tcl` is set as the bitstream `tcl.pre` hook. The ring loop itself is intentional. |
| Placement error mentions BUFR or clock region | Try the BUFG fallback described in the project notes: build with `-tclargs 2 4 16 1` or set generic `USE_BUFG=1`. |
| Pblock error says site not found | Use a valid origin for this FPGA; the documented examples use X4Y16, X4Y32, and the listed sweep origins. |
| Search records all have mean near 0 or 255 | The origin or parameter may be unusable. Check that the ring is oscillating and that the correct bitstream is programmed. |
| Every search result has mean 0 | Check the implementation report for 21 LUTs and 10 MUXF7s under `u_rng/u_loop`; confirm all RTL files are included and `DONT_TOUCH` is preserved. |
| `TimeoutError: board silent` | Press SW22, verify the port, then resume search with `--resume` or rerun the command. |
| AIS-31 fails | Try another candidate parameter and rerun the measurement; failures can occur for a candidate on a given chip. |
| NIST reports missing result directories | Run the STS `create-dir-script` from its `experiments/` directory. |

## Record results and screenshots

Keep a run log in `docs/results.md` with at least:

- Board and FPGA part number.
- Vivado version, loop type, parameter, placement origin, and bitstream/run identifier.
- Exact command, input capture, date, and operating conditions if known.
- Search range and usable-parameter rule.
- Counter sample count, mean, standard deviation, and saturation count.
- AIS-31 and NIST versions, test settings, and summary outputs.
- Utilization and throughput measurements.

Useful evidence screenshots include hierarchical utilization, timing summary, implemented device view with pblock at `SLICE_X4Y16`, ring schematic showing LUTs/F7MUXes, Hardware Manager with the device programmed, and a clear board photo with LEDs lit. Do not include photos that expose personal information or unrelated setup details.

## Generated files and GitHub

Commit RTL, constraints, scripts, host tools, documentation, and small result summaries. Keep machine-generated and large data out of Git unless there is a specific reason and the repository can host them:

- Vivado cache, project, and run directories (`.Xil/`, `.runs/`, `.cache/`, generated project folders).
- Bitstreams and programming files (`*.bit`, `*.ltx`).
- Large raw parameter-search, counter, and TRNG captures (for example, multi-megabyte `.bin` files).
- Temporary logs, Python virtual environments, and editor files.

Use `.gitignore` for those paths. If you share a small data sample, identify its origin, board, parameter, and purpose in the repository. Add a `LICENSE` file before publishing and choose a license only after confirming you have the right to distribute all included source and assets. Credit the paper and any third-party code or data you reuse.

## Paper reference and acknowledgements

This project reimplements and evaluates selected aspects of *On the Feasibility of TERO-based TRNG on Xilinx FPGAs* (FPL 2020). Consult the paper for its original design and reported baselines. This repository is an independent board port and experimental reproduction; it does not claim identical results or endorsement by the paper's authors.
