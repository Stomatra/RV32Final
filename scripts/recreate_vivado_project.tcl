# Recreate the Vivado project from tracked source files.
#
# Usage:
#   vivado -mode batch -source scripts/recreate_vivado_project.tcl
#
# The generated project lives in build/vivado and is intentionally ignored by
# Git. Commit HDL, constraints, COE files, XCI configuration, and Tcl scripts;
# do not commit the generated .xpr, runs, logs, reports, or bitstreams.

set script_dir [file normalize [file dirname [info script]]]
set origin_dir [file normalize [file join $script_dir ..]]
set project_dir [file normalize [file join $origin_dir build vivado]]
set project_name digital_twin
set part_name xc7k325tffg900-2

proc repo_path {relpath} {
    global origin_dir
    return [file normalize [file join $origin_dir $relpath]]
}

proc must_exist {path} {
    if {![file exists $path]} {
        error "Missing required file: $path"
    }
    return $path
}

proc repo_files {relpaths} {
    set out [list]
    foreach relpath $relpaths {
        lappend out [must_exist [repo_path $relpath]]
    }
    return $out
}

file mkdir $project_dir
create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set design_sources [repo_files [list \
    digital_twin.srcs/sources_1/imports/new/NPC.sv \
    digital_twin.srcs/sources_1/imports/new/MuxKey.v \
    digital_twin.srcs/sources_1/imports/new/MuxKeyInternal.v \
    digital_twin.srcs/sources_1/imports/new/ACTL.sv \
    digital_twin.srcs/sources_1/imports/new/CCTL.sv \
    digital_twin.srcs/sources_1/imports/new/Control.sv \
    digital_twin.srcs/sources_1/imports/new/Mask.sv \
    digital_twin.srcs/sources_1/imports/new/PC.sv \
    digital_twin.srcs/sources_1/imports/new/CSR.sv \
    digital_twin.srcs/sources_1/imports/new/ALU.sv \
    digital_twin.srcs/sources_1/imports/new/Divider.sv \
    digital_twin.srcs/sources_1/imports/new/defines.sv \
    digital_twin.srcs/sources_1/imports/new/IMMGEN.sv \
    digital_twin.srcs/sources_1/imports/new/RF.sv \
    digital_twin.srcs/sources_1/new/counter.sv \
    digital_twin.srcs/sources_1/new/display_seg.sv \
    digital_twin.srcs/sources_1/new/dram_driver.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen.sv \
    digital_twin.srcs/sources_1/new/hdmi_demo.sv \
    digital_twin.srcs/sources_1/new/hdmi_out_7series.sv \
    digital_twin.srcs/sources_1/new/hdmi_test_pattern.sv \
    digital_twin.srcs/sources_1/new/myCPU.sv \
    digital_twin.srcs/sources_1/new/perip_bridge.sv \
    digital_twin.srcs/sources_1/new/seg7.sv \
    digital_twin.srcs/sources_1/new/student_top.sv \
    digital_twin.srcs/sources_1/new/twin_controller.sv \
    digital_twin.srcs/sources_1/new/tmds_encoder.sv \
    digital_twin.srcs/sources_1/new/uart.sv \
    digital_twin.srcs/sources_1/new/uart_tx.sv \
    digital_twin.srcs/sources_1/new/uart_rx.sv \
    digital_twin.srcs/sources_1/new/video_timing_640x480.sv \
    digital_twin.srcs/sources_1/new/top.sv \
]]

set memory_sources [repo_files [list \
    digital_twin.srcs/sources_1/imports/test_src/dram.coe \
    digital_twin.srcs/sources_1/imports/test_src/irom.coe \
]]

set ip_sources [repo_files [list \
    digital_twin.srcs/sources_1/ip/DRAM/DRAM.xci \
    digital_twin.srcs/sources_1/ip/IROM/IROM.xci \
    digital_twin.srcs/sources_1/ip/pll_1/pll.xci \
]]

set constr_sources [repo_files [list \
    digital_twin.srcs/constrs_1/new/digital_twin.xdc \
]]

set sim_sources [repo_files [list \
    digital_twin.srcs/sim_1/new/tb_counter.sv \
    digital_twin.srcs/sim_1/new/tb_mul_helper_accel.sv \
    digital_twin.srcs/sim_1/new/tb_perf_load_use.sv \
    digital_twin.srcs/sim_1/new/tb_perf_forwarding.sv \
    digital_twin.srcs/sim_1/new/tb_perf_allu_stream.sv \
    digital_twin.srcs/sim_1/new/tb_CPU_perf_200m.sv \
    digital_twin.srcs/sim_1/new/tb_rv32i_isa.sv \
    digital_twin.srcs/sim_1/new/tb_perip_bridge.sv \
    digital_twin.srcs/sim_1/new/tb_myCPU.sv \
    digital_twin.srcs/sim_1/new/tb_uart.sv \
    digital_twin.srcs/sim_1/new/tb_csr_trap.sv \
    digital_twin.srcs/sim_1/new/tb_top.sv \
]]

add_files -norecurse -fileset sources_1 $design_sources
add_files -norecurse -fileset sources_1 $memory_sources
add_files -norecurse -fileset sources_1 $ip_sources
add_files -norecurse -fileset constrs_1 $constr_sources
add_files -norecurse -fileset sim_1 $sim_sources

set_property target_constrs_file [lindex $constr_sources 0] [get_filesets constrs_1]
set_property top top [get_filesets sources_1]
set_property top tb_top [get_filesets sim_1]

catch {set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] *.sv]}
catch {set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set ips [get_ips -quiet]
if {[llength $ips] > 0} {
    report_ip_status
    generate_target all $ips
}

puts "Vivado project recreated at: [file join $project_dir $project_name.xpr]"
close_project
