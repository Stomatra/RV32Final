open_project d:/digital_twin/digital_twin/digital_twin.xpr
set f [get_files d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/imports/new/myCPU.sv]
puts "COUNT=[llength $f]"
if {[llength $f] > 0} {
  puts "FILE=$f"
  catch {puts "IS_ENABLED=[get_property IS_ENABLED $f]"}
  catch {puts "USED_IN=[get_property USED_IN $f]"}
  catch {puts "USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $f]"}
  catch {puts "AUTO_DISABLED=[get_property AUTO_DISABLED $f]"}
  catch {puts "SCOPED_TO_REF=[get_property SCOPED_TO_REF $f]"}
  catch {puts "FILESET=[get_property FILESET_NAME $f]"}
}
set srcset [get_filesets sources_1]
puts "SRC_FILES_MATCH=[get_files -of_objects $srcset *myCPU.sv]"
close_project
exit
