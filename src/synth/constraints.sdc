create_clock -period 20 -name my_clk clk
#set_fix_hold [get_clocks my_clk]

set_input_delay 0.5 [all_inputs] -clock my_clk
set_output_delay 0.5 [all_outputs] -clock my_clk
set_load 0.1 [all_outputs]
set_max_fanout 1 [all_inputs]
set_fanout_load 8 [all_outputs]
