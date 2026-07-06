puts "=== place_design help excerpt ==="
catch {place_design -help} place_help
puts $place_help
puts "=== phys_opt_design help excerpt ==="
catch {phys_opt_design -help} phys_help
puts $phys_help
puts "=== route_design help excerpt ==="
catch {route_design -help} route_help
puts $route_help
exit
