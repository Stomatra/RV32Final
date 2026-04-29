open_checkpoint {d:/digital_twin/digital_twin/digital_twin.runs/synth_1/top.dcp}
set nets [lsort [get_nets -hier {student_top_inst/Core_cpu/O71[*]}]]
puts [format {FOUND_NETS %d} [llength $nets]]
foreach net $nets {
    puts [format {NET %s} $net]
    set driver_pins [get_pins -leaf -of_objects $net -filter {DIRECTION == OUT}]
    foreach pin $driver_pins {
        set cell [get_cells -of_objects $pin]
        puts [format {  DRIVER_PIN %s} $pin]
        puts [format {  DRIVER_CELL %s} $cell]
        catch {puts [format {  DRIVER_REF %s} [get_property REF_NAME $cell]]}
    }
    set load_pins [lsort [get_pins -leaf -of_objects $net -filter {DIRECTION == IN}]]
    puts [format {  LOAD_COUNT %d} [llength $load_pins]]
    foreach pin [lrange $load_pins 0 19] {
        puts [format {  LOAD_PIN %s} $pin]
    }
}
close_design
exit
