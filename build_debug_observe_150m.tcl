set origin_dir [file dirname [file normalize [info script]]]
set part_name "xc7k325tffg900-2"
set build_dir [file join $origin_dir "debug_observe_150m_build"]
set synth_dcp [file join $build_dir "top_debug_observe_synth.dcp"]
set debug_bit [file join $origin_dir "top_debug_observe_withoutmext_irom_v2_150m.bit"]
set timing_rpt [file join $origin_dir "timing_debug_observe_150m.rpt"]
set paths_rpt [file join $origin_dir "timing_debug_observe_150m_paths.rpt"]
set summary_txt [file join $origin_dir "timing_debug_observe_150m_summary.txt"]

file mkdir $build_dir

proc collect_sources {origin_dir} {
    set design_dir [file join $origin_dir "digital_twin.srcs" "sources_1" "new"]
    set imports_dir [file join $origin_dir "digital_twin.srcs" "sources_1" "imports" "new"]

    set design_names {}
    set design_sources {}
    foreach f [lsort [concat \
        [glob -nocomplain -directory $design_dir *.sv] \
        [glob -nocomplain -directory $design_dir *.v]]] {
        lappend design_names [file tail $f]
        lappend design_sources $f
    }

    set import_sources {}
    foreach f [lsort [concat \
        [glob -nocomplain -directory $imports_dir *.sv] \
        [glob -nocomplain -directory $imports_dir *.v]]] {
        if {[lsearch -exact $design_names [file tail $f]] < 0} {
            lappend import_sources $f
        }
    }

    return [concat $import_sources $design_sources]
}

proc path_pin_name {path prop fallback_prop} {
    if {[catch {set pin [get_property $prop $path]}] || $pin eq ""} {
        if {[catch {set pin [get_property $fallback_prop $path]}] || $pin eq ""} {
            return ""
        }
    }
    return [get_property NAME $pin]
}

proc first_cell_by_ref {ref_name} {
    set cells [get_cells -hier -filter "REF_NAME == $ref_name"]
    if {[llength $cells] == 0} {
        error "Cannot find cell with REF_NAME == $ref_name"
    }
    return [lindex $cells 0]
}

set sources [collect_sources $origin_dir]
set irom_stub [file join $origin_dir "digital_twin.gen" "sources_1" "ip" "IROM" "IROM_stub.v"]
set pll_stub [file join $origin_dir "digital_twin.gen" "sources_1" "ip" "pll" "pll_stub.v"]
set irom_dcp [file join $origin_dir "digital_twin.gen" "sources_1" "ip" "IROM" "IROM.dcp"]
set pll_dcp [file join $origin_dir "digital_twin.gen" "sources_1" "ip" "pll" "pll.dcp"]
set xdc_file [file join $origin_dir "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]

foreach required [list $irom_stub $pll_stub $irom_dcp $pll_dcp $xdc_file] {
    if {![file exists $required]} {
        error "Required file not found: $required"
    }
}

create_project -in_memory -part $part_name
set_property source_mgmt_mode None [current_project]
set_property target_language Verilog [current_project]
set_property verilog_define {DEBUG_OBSERVE_MMIO} [current_fileset]

read_verilog -sv $sources
read_verilog $irom_stub
read_verilog $pll_stub

puts "DEBUG_DEFINE=DEBUG_OBSERVE_MMIO"
puts "SOURCE_COUNT=[llength $sources]"
puts "IROM_DCP=$irom_dcp"
puts "PLL_DCP=$pll_dcp"

synth_design -top top -part $part_name -flatten_hierarchy rebuilt
write_checkpoint -force $synth_dcp

set irom_cell [first_cell_by_ref IROM]
puts "IROM_CELL=[get_property NAME $irom_cell]"
read_checkpoint -cell $irom_cell $irom_dcp

set pll_cell [first_cell_by_ref pll]
puts "PLL_CELL=[get_property NAME $pll_cell]"
read_checkpoint -cell $pll_cell $pll_dcp

if {[llength [get_clocks -quiet sys_clk_p]] == 0} {
    create_clock -period 5.000 -name sys_clk_p [get_ports i_sys_clk_p]
    set_input_jitter [get_clocks sys_clk_p] 0.050
}

read_xdc $xdc_file
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
phys_opt_design -directive AggressiveExplore

report_timing_summary -max_paths 10 -report_unconstrained -warn_on_violation -file $timing_rpt
report_timing -delay_type max -max_paths 10 -sort_by group -file $paths_rpt
write_bitstream -force $debug_bit

set worst_paths [get_timing_paths -setup -max_paths 1 -nworst 1]
set worst_slack ""
set worst_source ""
set worst_dest ""
if {[llength $worst_paths] > 0} {
    set worst_path [lindex $worst_paths 0]
    set worst_slack [get_property SLACK $worst_path]
    set worst_source [path_pin_name $worst_path STARTPOINT_PIN STARTPOINT]
    set worst_dest [path_pin_name $worst_path ENDPOINT_PIN ENDPOINT]
}

set fp [open $summary_txt w]
puts $fp "DEBUG_DEFINE=DEBUG_OBSERVE_MMIO"
puts $fp "DEBUG_BIT=$debug_bit"
puts $fp "TIMING_REPORT=$timing_rpt"
puts $fp "PATHS_REPORT=$paths_rpt"
puts $fp "WORST_SETUP_SLACK=$worst_slack"
puts $fp "WORST_SETUP_SOURCE=$worst_source"
puts $fp "WORST_SETUP_DESTINATION=$worst_dest"
close $fp

puts "DEBUG_BIT=$debug_bit"
puts "TIMING_REPORT=$timing_rpt"
puts "PATHS_REPORT=$paths_rpt"
puts "SUMMARY_TEXT=$summary_txt"
puts "WORST_SETUP_SLACK=$worst_slack"
puts "WORST_SETUP_SOURCE=$worst_source"
puts "WORST_SETUP_DESTINATION=$worst_dest"
