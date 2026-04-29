open_project digital_twin.xpr
set_property top tb_myCPU [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_project
exit
