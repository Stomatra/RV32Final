open_project D:/digital_twin/digital_twin/digital_twin.xpr
set_property top tb_myCPU [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {1200ms} -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
