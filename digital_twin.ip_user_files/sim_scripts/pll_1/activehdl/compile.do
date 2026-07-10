transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xpm
vlib activehdl/xil_defaultlib

vmap xpm activehdl/xpm
vmap xil_defaultlib activehdl/xil_defaultlib

vlog -work xpm  -sv2k12 "+incdir+../../../ipstatic" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../../digital_twin.gen/sources_1/ip/pll" -l xpm -l xil_defaultlib \
"E:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -93  \
"E:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../ipstatic" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../../digital_twin.gen/sources_1/ip/pll" -l xpm -l xil_defaultlib \
"../../../../digital_twin.gen/sources_1/ip/pll/pll_clk_wiz.v" \
"../../../../digital_twin.gen/sources_1/ip/pll/pll.v" \

vlog -work xil_defaultlib \
"glbl.v"

