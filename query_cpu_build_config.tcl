proc print_project_config {label project_path} {
    if {![file exists $project_path]} {
        puts "${label}_PROJECT_MISSING=[file normalize $project_path]"
        return
    }

    open_project $project_path
    set fs [get_filesets sources_1]
    puts "${label}_PROJECT=[file normalize $project_path]"
    puts "${label}_TOP=[get_property top $fs]"
    puts "${label}_VERILOG_DEFINE=[get_property verilog_define $fs]"
    puts "${label}_SOURCE_COUNT=[llength [get_files -of_objects $fs]]"

    foreach pattern [list "*myCPU.sv" "*student_top.sv" "*top.sv" "*Divider.sv" "*Multiplier.sv" "*z_light_unit.sv" "*IROM.xci" "*DRAM.xci"] {
        set files [get_files -quiet -of_objects $fs $pattern]
        if {[llength $files] == 0} {
            puts "${label}_FILE_${pattern}=<missing>"
        } else {
            foreach f $files {
                puts "${label}_FILE_${pattern}=[file normalize $f]"
            }
        }
    }

    close_project
}

print_project_config FULL digital_twin.xpr
print_project_config INDEPENDENT_WITHMEXT build_outputs/cpu_hdmi_ls_withMext_project/cpu_hdmi_ls_withMext.xpr
print_project_config INDEPENDENT_LEGACY_WITHMEXT build_outputs/cpu_hdmi_ls_project/cpu_hdmi_ls.xpr
print_project_config INDEPENDENT_WITHOUTMEXT build_outputs/cpu_hdmi_ls_withoutMext_project/cpu_hdmi_ls_withoutMext.xpr
