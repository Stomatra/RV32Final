open_project D:/digital_twin/digital_twin/digital_twin.xpr
open_run synth_1
set cells [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.bram.*} | head -5]
foreach c [lrange [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.bram.*}] 0 2] {
    puts "CELL: [get_property NAME \]"
    puts "INIT_00: [get_property INIT_00 \]"
    puts "INIT_01: [get_property INIT_01 \]"
}
close_project
