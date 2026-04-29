open_project d:/digital_twin/digital_twin/digital_twin.xpr
set f [get_files d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/imports/new/myCPU.sv]
puts "FILE_TYPE=[get_property FILE_TYPE $f]"
puts "LIBRARY=[get_property LIBRARY $f]"
close_project
exit
