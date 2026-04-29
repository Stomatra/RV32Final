@echo off
cd /d "d:\digital_twin\digital_twin"
call "C:\Xilinx\Vivado\2023.2\settings64.bat"
vivado -mode batch -source resynth.tcl
