set origin_dir [file normalize [pwd]]
set routed_dcp [file join $origin_dir "digital_twin.runs" "impl_1" "top_routed.dcp"]
set physopt_dcp [file join $origin_dir "digital_twin.runs" "impl_1" "top_physopt.dcp"]

proc worst_setup_slack {} {
    set paths [get_timing_paths -setup -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        return 999.0
    }
    return [get_property SLACK [lindex $paths 0]]
}

proc write_candidate {tag} {
    global origin_dir
    set bit_file [file join $origin_dir "top_normal_${tag}.bit"]
    set rpt_file [file join $origin_dir "top_timing_summary_${tag}.rpt"]
    report_timing_summary -file $rpt_file -warn_on_violation
    set slack [worst_setup_slack]
    puts "TIMING_RESULT $tag WNS=$slack"
    write_checkpoint -force [file join $origin_dir "top_${tag}.dcp"]
    write_bitstream -force $bit_file
    return $slack
}

set best_tag ""
set best_slack -999.0

if {[file exists $routed_dcp]} {
    puts "Trying post-route phys_opt from $routed_dcp"
    open_checkpoint $routed_dcp
    if {[catch {phys_opt_design -directive AggressiveExplore} msg]} {
        puts "WARN: post-route phys_opt failed: $msg"
    } else {
        catch {route_design -directive HigherDelayCost}
        set slack [write_candidate "postroute_physopt"]
        set best_tag "postroute_physopt"
        set best_slack $slack
    }
    close_design
}

if {$best_slack < 0.0 && [file exists $physopt_dcp]} {
    foreach directive {Explore NoTimingRelaxation MoreGlobalIterations} {
        puts "Trying route directive $directive from $physopt_dcp"
        open_checkpoint $physopt_dcp
        if {[catch {route_design -directive $directive} msg]} {
            puts "WARN: route $directive failed: $msg"
            close_design
            continue
        }
        set tag "route_${directive}"
        set slack [write_candidate $tag]
        if {$slack > $best_slack} {
            set best_slack $slack
            set best_tag $tag
        }
        close_design
        if {$slack >= 0.0} {
            break
        }
    }
}

if {$best_tag ne ""} {
    file copy -force [file join $origin_dir "top_normal_${best_tag}.bit"] [file join $origin_dir "top_normal_best.bit"]
}
if {$best_slack >= 0.0 && $best_tag ne ""} {
    file copy -force [file join $origin_dir "top_normal_${best_tag}.bit"] [file join $origin_dir "top_normal_timing_clean.bit"]
}

puts "BEST_TIMING_RESULT $best_tag WNS=$best_slack"
