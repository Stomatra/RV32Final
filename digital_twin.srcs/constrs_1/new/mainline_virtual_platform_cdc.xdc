# Virtual-platform status paths cross between the 283 MHz CPU clock and the
# 50 MHz UART/twin-controller clock. They are slow debug/control interfaces,
# not single-cycle CPU datapaths.
#
# Keep the exception narrow:
# - CPU-domain LED/SEG display state sampled by the first 50 MHz sync flop in
#   top.sv, then read by twin_controller.
# - twin_controller SW/KEY state sampled by the first CPU-domain sync flop in
#   top.sv, then read through MMIO.
# counter.sv has explicit CDC synchronizers too. Cut only the asynchronous
# launch-to-first-sync-flop paths and leave same-domain sync2 paths timed.

set bridge_cells [get_cells -hier -regexp {student_top_inst/bridge_inst/.*}]
set bridge_regs [filter $bridge_cells {IS_SEQUENTIAL == 1}]
set twin_input_regs [get_cells -hier -regexp {twin_controller_inst/(sw_reg\[[0-9]+\]|key_reg\[[0-9]+\])}]
set top_cpu_input_sync1_regs [get_cells -hier -regexp {(virtual_key_cpu_ff1_reg|virtual_sw_cpu_ff1_reg)(\[[0-9]+\])?}]
set top_status_sync1_regs [get_cells -hier -regexp {(student_virtual_led_ff1_reg|student_virtual_seg_ff1_reg)(\[[0-9]+\])?}]
set counter_cpu_cmd_regs [get_cells -hier -regexp {student_top_inst/bridge_inst/counter_inst/(cmd_toggle_cpu_reg|cmd_value_cpu_reg)}]
set counter_cmd_sync1_regs [get_cells -hier -regexp {student_top_inst/bridge_inst/counter_inst/(cmd_toggle_sync1_reg|cmd_value_sync1_reg)}]
set counter_cnt_regs [get_cells -hier -regexp {student_top_inst/bridge_inst/counter_inst/cnt_ms_reg\[[0-9]+\]}]
set counter_gray_sync1_regs [get_cells -hier -regexp {student_top_inst/bridge_inst/counter_inst/cnt_ms_gray_sync1_reg\[[0-9]+\]}]

set_false_path \
    -from $bridge_regs \
    -to   $top_status_sync1_regs

set_false_path \
    -from $twin_input_regs \
    -to   $top_cpu_input_sync1_regs

set_false_path \
    -from $counter_cpu_cmd_regs \
    -to   $counter_cmd_sync1_regs

set_false_path \
    -from $counter_cnt_regs \
    -to   $counter_gray_sync1_regs
