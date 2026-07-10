open_project digital_twin.xpr

set synth_status [get_property STATUS [get_runs synth_1]]
set synth_needs_refresh false
catch {set synth_needs_refresh [get_property NEEDS_REFRESH [get_runs synth_1]]}
puts "synth_1 initial status: $synth_status NEEDS_REFRESH=$synth_needs_refresh"

if {![string match "*Complete*" $synth_status] || $synth_needs_refresh} {
    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
} else {
    puts "Reusing existing synth_1 checkpoint"
}

puts "synth_1 status: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 did not complete"
}

open_run synth_1

catch {disconnect_debug_port [get_debug_ports -quiet *]}
catch {delete_debug_core [get_debug_cores -quiet *]}

proc obj_name {obj} {
    return [get_property NAME $obj]
}

proc select_one {what matches} {
    if {[llength $matches] == 0} {
        error "No net matched $what"
    }
    if {[llength $matches] > 1} {
        puts "Multiple matches for $what, using first:"
        foreach match $matches {
            puts "  [obj_name $match]"
        }
    }
    return [lindex $matches 0]
}

proc find_by_net_regexp {what patterns} {
    foreach pattern $patterns {
        set matches [get_nets -hier -quiet -regexp $pattern]
        if {[llength $matches] > 0} {
            return [select_one $what $matches]
        }
    }
    return ""
}

proc find_by_q_pin_regexp {what patterns} {
    foreach pattern $patterns {
        set pins [get_pins -hier -quiet -regexp $pattern]
        if {[llength $pins] > 0} {
            set nets [get_nets -quiet -of_objects $pins]
            if {[llength $nets] > 0} {
                return [select_one $what $nets]
            }
        }
    }
    return ""
}

proc find_scalar_net {leaf} {
    set what "scalar probe $leaf"
    set net [find_by_net_regexp $what [list \
        [format {(^|.*/)%s$} $leaf] \
        [format {(^|.*/)%s_reg$} $leaf] \
    ]]
    if {$net ne ""} {
        return $net
    }

    set net [find_by_q_pin_regexp $what [list \
        [format {(^|.*/)%s_reg/Q$} $leaf] \
    ]]
    if {$net ne ""} {
        return $net
    }

    puts "Available debug-like nets:"
    foreach candidate [get_nets -hier -quiet -regexp {(^|.*/)dbg_.*}] {
        puts "  [obj_name $candidate]"
    }
    error "No scalar net matched leaf: $leaf"
}

proc find_bus_bit_net {leaf index} {
    set what [format {bus probe %s[%d]} $leaf $index]
    set net [find_by_net_regexp $what [list \
        [format {(^|.*/)%s\[%d\]$} $leaf $index] \
        [format {(^|.*/)%s_reg\[%d\]$} $leaf $index] \
    ]]
    if {$net ne ""} {
        return $net
    }

    set net [find_by_q_pin_regexp $what [list \
        [format {(^|.*/)%s_reg\[%d\]/Q$} $leaf $index] \
    ]]
    if {$net ne ""} {
        return $net
    }

    error "No bit net matched $leaf\[$index\]"
}

proc find_probe_nets {leaf width} {
    if {$width == 1} {
        set net [find_scalar_net $leaf]
        puts "Selected ILA net $leaf -> [obj_name $net]"
        return $net
    }

    set nets {}
    for {set index 0} {$index < $width} {incr index} {
        set bit_net [find_bus_bit_net $leaf $index]
        lappend nets $bit_net
    }
    set msb [expr {$width - 1}]
    puts "Selected ILA bus ${leaf}\[${msb}:0\]"
    return $nets
}

proc find_clock_net {} {
    set exact [get_nets -hier -quiet -regexp {(^|.*/)cpu_clk$}]
    foreach net $exact {
        if {[obj_name $net] eq "cpu_clk"} {
            puts "Selected ILA clock -> [obj_name $net]"
            return $net
        }
    }
    if {[llength $exact] > 0} {
        set net [lindex $exact 0]
        puts "Selected ILA clock -> [obj_name $net]"
        return $net
    }

    set candidates [get_nets -hier -quiet -filter {(NAME =~ *cpu_clk* || NAME =~ *clk_out2*) && NAME !~ *u_ila*}]
    puts "ILA clock candidates:"
    foreach net $candidates {
        puts "  [obj_name $net]"
    }

    foreach net $candidates {
        set name [obj_name $net]
        if {[string match *clk_out2_pll $name]} {
            continue
        }
        if {[string match *pll_inst/inst/* $name]} {
            continue
        }
        puts "Selected ILA clock -> $name"
        return $net
    }

    error "No clock net matched cpu_clk/clk_out2"
}

set out_dir [file normalize [pwd]]
file mkdir $out_dir

set core_name ila_cpu
create_debug_core $core_name ila
set_property C_DATA_DEPTH 2048 [get_debug_cores $core_name]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores $core_name]
set_property ALL_PROBE_SAME_MU true [get_debug_cores $core_name]

connect_debug_port $core_name/clk [find_clock_net]

set probe_defs {
    {dbg_pc_q 32}
    {dbg_pc_next 32}
    {dbg_ifid_pc 32}
    {dbg_ifid_instr 32}
    {dbg_ifid_valid 1}
    {dbg_idex_pc 32}
    {dbg_idex_valid 1}
    {dbg_idex_pc_sel 2}
    {dbg_idex_rd 5}
    {dbg_ex_pc_target 32}
    {dbg_ex_br_take 1}
    {dbg_ex_pc_redirect 1}
    {dbg_ex_trap_enter 1}
    {dbg_ex_trap_return 1}
    {dbg_exmem_pc 32}
    {dbg_exmem_alu_y 32}
    {dbg_exmem_valid 1}
    {dbg_exmem_mem_req 1}
    {dbg_exmem_mem_write 1}
    {dbg_exmem_mem_mask 2}
    {dbg_exmem_rd 5}
    {dbg_memwb_pc 32}
    {dbg_memwb_wdata 32}
    {dbg_memwb_valid 1}
    {dbg_memwb_rf_we 1}
    {dbg_memwb_rd 5}
    {dbg_perip_addr 32}
    {dbg_perip_wdata 32}
    {dbg_perip_rdata 32}
    {dbg_perip_wen 1}
    {dbg_perip_mask 2}
    {dbg_load_use_hazard 1}
    {dbg_pc_ex_hazard 1}
    {dbg_pc_mem_hazard 1}
    {dbg_mem_load_stall 1}
    {dbg_id_mul_helper_hit 1}
    {dbg_div_busy 1}
    {dbg_div_done 1}
    {dbg_m_stall 1}
    {dbg_csr_mepc 32}
    {dbg_rf_x1 32}
}

set probe_index 0
foreach probe_def $probe_defs {
    set leaf [lindex $probe_def 0]
    set width [lindex $probe_def 1]
    set port_name [format "%s/probe%d" $core_name $probe_index]
    if {[llength [get_debug_ports -quiet $port_name]] == 0} {
        create_debug_port $core_name probe
    }
    set_property PORT_WIDTH $width [get_debug_ports $port_name]
    connect_debug_port $port_name [find_probe_nets $leaf $width]
    puts "Connected $port_name width=$width to $leaf"
    incr probe_index
}

report_property [get_debug_cores $core_name]

opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive HigherDelayCost

write_debug_probes -force [file join $out_dir ila_0.ltx]

report_timing_summary -max_paths 10 -report_unconstrained -file [file join $out_dir top_timing_summary_ila.rpt]
report_utilization -file [file join $out_dir top_utilization_ila.rpt]

write_bitstream -force [file join $out_dir top_ila.bit]

close_project
