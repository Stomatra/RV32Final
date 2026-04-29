open_project d:/digital_twin/digital_twin/digital_twin.xpr
set f [get_files d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv]
foreach p {IS_GLOBAL_INCLUDE IS_INCLUDE_FILE FILESET_NAME SCOPED_TO_REF SCOPED_TO_CELLS} {
  if {[catch {set v [get_property $p $f]}]} {set v "<NA>"}
  puts "$p=$v"
}
close_project
exit
