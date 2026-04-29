open_checkpoint {d:/digital_twin/digital_twin/inspect_d_after_place.dcp}
set out [open {d:/digital_twin/digital_twin/query_placed_d_nets.txt} w]
set targets {0 1 2 5 6 7 8 9 10 11}
foreach idx $targets {
    set pattern [format {^student_top_inst/Core_cpu/D\[%d\]$} $idx]
    set net [get_nets -hier -regexp $pattern]
    puts $out [format {D_INDEX %d COUNT %d} $idx [llength $net]]
    foreach one_net $net {
        puts $out [format {NET %s} $one_net]
        set driver_pins [get_pins -leaf -of_objects $one_net -filter {DIRECTION == OUT}]
        foreach pin $driver_pins {
            set cell [get_cells -of_objects $pin]
            puts $out [format {  DRIVER_PIN %s} $pin]
            puts $out [format {  DRIVER_CELL %s} $cell]
            catch {puts $out [format {  DRIVER_REF %s} [get_property REF_NAME $cell]]}
        }
        set load_pins [lsort [get_pins -leaf -of_objects $one_net -filter {DIRECTION == IN}]]
        puts $out [format {  LOAD_COUNT %d} [llength $load_pins]]
        foreach pin [lrange $load_pins 0 39] {
            set cell [get_cells -of_objects $pin]
            puts $out [format {  LOAD_PIN %s} $pin]
            puts $out [format {  LOAD_CELL %s} $cell]
            catch {puts $out [format {  LOAD_REF %s} [get_property REF_NAME $cell]]}
        }
    }
}
close $out
close_design
exit
