open_hw_manager
connect_hw_server
set targets [get_hw_targets]
puts "Found [llength $targets] target(s)"
if {[llength $targets] > 0} {
  current_hw_target [lindex $targets 0]
  open_hw_target
  set dev [current_hw_device]
  puts "Device: $dev"
  set_property PROGRAM.FILE {/home/haitaoz/work/FPGA_Prj/RiscV_WebSoC/build_xilinx/RiscV_WebSoC_fw.bit} $dev
  program_hw_devices $dev
  puts "PROGRAMMING SUCCESS"
} else {
  puts "ERROR: No hardware targets found"
}
close_hw_manager
