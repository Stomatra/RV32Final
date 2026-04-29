"""
Vivado build automation - re-synthesize and implement with mem_load_stall fix
"""
import subprocess
import os
import sys

PROJECT_DIR = r"d:\digital_twin\digital_twin"
PROJECT_FILE = os.path.join(PROJECT_DIR, "digital_twin.xpr")
# Try to find Vivado
import shutil
VIVADO_PATH = shutil.which("vivado") or r"C:\Xilinx\Vivado\2023.2\bin\vivado"
print(f"Using Vivado: {VIVADO_PATH}")

# TCL script for Vivado
tcl_script = """
open_project digital_twin.xpr

# Synthesis
puts "\\n===== SYNTHESIS ====="
reset_runs synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis
open_run synth_1
puts [get_property STATS.SYNTHESIZED [get_runs synth_1]]
report_timing_summary -file synth_timing_summary.txt
close_run synth_1

# Implementation
puts "\\n===== IMPLEMENTATION ====="
reset_runs impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Generate bitstream
puts "\\n===== BITSTREAM GENERATION ====="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Report timing
open_run impl_1
report_timing_summary -file impl_timing_summary.txt
puts "\\nTiming Report:"
catch {exec grep -i "slack" impl_timing_summary.txt}
close_run impl_1

puts "\\n===== BUILD COMPLETE ====="
puts "Bitfile: digital_twin.runs/impl_1/top.bit"
close_project
"""

# Write TCL script
tcl_file = os.path.join(PROJECT_DIR, "automated_build.tcl")
with open(tcl_file, "w") as f:
    f.write(tcl_script)

# Run Vivado
os.chdir(PROJECT_DIR)
cmd = [VIVADO_PATH, "-mode", "batch", "-source", tcl_file, "-log", "vivado_auto_build.log"]
print(f"Running: {' '.join(cmd)}")
print(f"Working dir: {PROJECT_DIR}\n")

result = subprocess.run(cmd, capture_output=True, text=True)
print("STDOUT:")
print(result.stdout)
if result.stderr:
    print("\nSTDERR:")
    print(result.stderr)

print(f"\nReturn code: {result.returncode}")
if result.returncode == 0:
    bitfile = os.path.join(PROJECT_DIR, "digital_twin.runs", "impl_1", "top.bit")
    if os.path.exists(bitfile):
        print(f"✓ Bitfile generated: {bitfile}")
        print(f"  Size: {os.path.getsize(bitfile) / 1024:.1f} KB")
    else:
        print("✗ Bitfile not found - check Vivado build log for errors")
else:
    print("✗ Vivado build failed")
    with open(os.path.join(PROJECT_DIR, "vivado_auto_build.log"), "r") as f:
        print("\nVivado log (last 50 lines):")
        lines = f.readlines()
        for line in lines[-50:]:
            print(line.rstrip())
