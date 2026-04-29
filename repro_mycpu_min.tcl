create_project -in_memory -part xc7k325tffg900-2
read_verilog -sv d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/top.sv
read_verilog -sv d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/student_top.sv
read_verilog -sv d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv
synth_design -top top -part xc7k325tffg900-2
exit
