open_project d:/digital_twin/digital_twin/digital_twin.xpr
set srcset [get_filesets sources_1]
puts "MYCPU_IN_SOURCESET=[get_files -of_objects $srcset *myCPU.sv]"
close_project
exit
