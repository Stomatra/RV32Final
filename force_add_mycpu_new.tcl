open_project d:/digital_twin/digital_twin/digital_twin.xpr
add_files -fileset sources_1 -norecurse d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv
set f [get_files d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv]
set_property FILE_TYPE SystemVerilog $f
set_property IS_ENABLED true $f
set_property USED_IN_SYNTHESIS true $f
set_property USED_IN_IMPLEMENTATION true $f
set_property USED_IN_SIMULATION true $f
update_compile_order -fileset sources_1
save_project
puts "ADDED_NEW_MYCPU=[get_files -of_objects [get_filesets sources_1] *sources_1/new/myCPU.sv]"
close_project
exit
