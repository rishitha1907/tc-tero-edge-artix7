## ===========================================================================
## edge_a7_tero.xdc -- EDGE Artix-7 (XC7A35T-1FTG256C), TC-TERO reproduction
## Pins from the EDGE Artix 7 user manual (allaboutfpga.com, rev 3.0).
## ===========================================================================

## ---- 50 MHz oscillator Y2 -> N11 (MRCC)
set_property -dict { PACKAGE_PIN N11 IOSTANDARD LVCMOS33 } [get_ports clk50]
create_clock -name clk50 -period 20.000 [get_ports clk50]

## ---- centre push button SW22 (active high, 10k pull-down) = reset
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports btn_rst]

## ---- USB-UART (FT2232H)
set_property -dict { PACKAGE_PIN C4 IOSTANDARD LVCMOS33 } [get_ports uart_txd]
set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports uart_rxd]

## ---- LEDs D3..D19 (led[0] = rightmost)
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN H3  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN L3  IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN L2  IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN K3  IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN K5  IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN P6  IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN R7  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN R6  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN T5  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN R5  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## ---- configuration
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## ---- TERO output clock (through BUFR). Asynchronous to the system clock.
create_clock -name tero_clk -period 5.000 [get_pins -hierarchical -filter {NAME =~ *u_rng/*u_bufr/O}]
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk50] \
    -group [get_clocks tero_clk]

## ---- the ring is an intentional combinational loop
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *u_rng/u_loop/*}]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
