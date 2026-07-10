"""Vivado build automation for the source-only checkout."""

from pathlib import Path
import shutil
import subprocess
import sys


REPO_DIR = Path(__file__).resolve().parent
BUILD_DIR = REPO_DIR / "build"
PROJECT_FILE = BUILD_DIR / "vivado" / "digital_twin.xpr"
RECREATE_TCL = REPO_DIR / "scripts" / "recreate_vivado_project.tcl"
VIVADO_PATH = shutil.which("vivado") or r"C:\Xilinx\Vivado\2023.2\bin\vivado.bat"


def run(cmd):
    print("Running:", " ".join(str(part) for part in cmd))
    result = subprocess.run(cmd, cwd=REPO_DIR)
    if result.returncode != 0:
        sys.exit(result.returncode)


def main():
    print(f"Using Vivado: {VIVADO_PATH}")
    BUILD_DIR.mkdir(exist_ok=True)

    if not PROJECT_FILE.exists():
        run(
            [
                VIVADO_PATH,
                "-mode",
                "batch",
                "-source",
                str(RECREATE_TCL),
                "-log",
                str(BUILD_DIR / "recreate_vivado_project.log"),
                "-journal",
                str(BUILD_DIR / "recreate_vivado_project.jou"),
            ]
        )

    build_tcl = BUILD_DIR / "automated_build.tcl"
    build_tcl.write_text(
        f"""
open_project {{{PROJECT_FILE.as_posix()}}}

puts "\\n===== SYNTHESIS ====="
reset_runs synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

open_run synth_1
report_timing_summary -file {{{(BUILD_DIR / "synth_timing_summary.txt").as_posix()}}}
close_run synth_1

puts "\\n===== IMPLEMENTATION ====="
reset_runs impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

puts "\\n===== BITSTREAM GENERATION ====="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

open_run impl_1
report_timing_summary -file {{{(BUILD_DIR / "impl_timing_summary.txt").as_posix()}}}
close_run impl_1

puts "\\n===== BUILD COMPLETE ====="
set bitfile [file join [get_property DIRECTORY [current_project]] digital_twin.runs impl_1 top.bit]
puts "Bitfile: $bitfile"
close_project
""".lstrip(),
        encoding="utf-8",
    )

    run(
        [
            VIVADO_PATH,
            "-mode",
            "batch",
            "-source",
            str(build_tcl),
            "-log",
            str(BUILD_DIR / "vivado_auto_build.log"),
            "-journal",
            str(BUILD_DIR / "vivado_auto_build.jou"),
        ]
    )


if __name__ == "__main__":
    main()
