# constraints.tcl
#
# This file is where design timing constraints are defined for Genus and Innovus.
# Many constraints can be written directly into the Hammer config files. However, 
# you may manually define constraints here as well.
#

# Active timing constraints for Genus/Innovus.
# Keep the design clock definition here and leave cfg.yml free of duplicate
# custom_sdc_constraints so this file is the single source of truth.

# 100 MHz system clock
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks clk]

# Setup: IO delay = half period
set_input_delay  5.0 -max -clock [get_clocks clk] [all_inputs]
set_output_delay 5.0 -max -clock [get_clocks clk] [all_outputs]

# Hold: IO delay = 0
set_input_delay  0.0 -min -clock [get_clocks clk] [all_inputs]
set_output_delay 0.0 -min -clock [get_clocks clk] [all_outputs]
