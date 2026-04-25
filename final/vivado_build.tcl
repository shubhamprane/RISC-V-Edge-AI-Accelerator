# Vivado Build Script — NeuroCore Systolic Upgrade
# Target: Nexys A7 (xc7a100tcsg324-1)

create_project -in_memory -part xc7a100tcsg324-1

# --- RTL Sources ---
read_verilog [glob rtl/core/*.v]
read_verilog [glob rtl/coprocessor/*.v]
read_verilog [glob rtl/memory/*.v]
read_verilog [glob rtl/top/*.v]

set_property include_dirs {rtl/core} [current_fileset]
read_xdc constraints/nexys_a7.xdc

# --- Pre-synthesis: run unit testbenches via xsim ---
puts "=== Running unit testbenches ==="

proc run_tb {tb_name tb_file} {
    set all_rtl [concat [glob rtl/core/*.v] [glob rtl/coprocessor/*.v] \
                        [glob rtl/memory/*.v] [glob rtl/top/*.v]]
    set src_list [concat $all_rtl [list $tb_file]]
    set rc1 [catch {exec xvlog -sv {*}$src_list} out1]
    puts $out1
    if {$rc1 != 0} { puts "COMPILE FAIL: $tb_name"; return 1 }
    set rc2 [catch {exec xelab -debug typical $tb_name -s ${tb_name}_snap} out2]
    puts $out2
    if {$rc2 != 0} { puts "ELAB FAIL: $tb_name"; return 1 }
    set rc3 [catch {exec xsim ${tb_name}_snap -R} out3]
    puts $out3
    if {[string match "*FAIL*" $out3]} { puts "SIM FAIL: $tb_name"; return 1 }
    puts "PASS: $tb_name"
    return 0
}

set fail 0
set fail [expr $fail + [run_tb tb_pe               tb_pe.v]]
set fail [expr $fail + [run_tb tb_argmax           tb_argmax.v]]
set fail [expr $fail + [run_tb tb_systolic_corrected tb_systolic_corrected.v]]
set fail [expr $fail + [run_tb tb_uart_full        tb_uart_full.v]]
set fail [expr $fail + [run_tb tb_coprocessor      tb_coprocessor.v]]
set fail [expr $fail + [run_tb tb_top_uart_to_display tb_top_uart_to_display.v]]

if {$fail > 0} {
    puts "ERROR: $fail testbench(es) failed. Aborting synthesis."
    exit 1
}
puts "=== All testbenches PASSED. Proceeding to synthesis... ==="

# --- Synthesis ---
synth_design -top top_fpga -part xc7a100tcsg324-1

# --- Implementation ---
opt_design
place_design
route_design

# --- Timing check ---
# set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
# puts "Worst Negative Slack: $wns ns"

# --- Bitstream ---
write_bitstream -force neurocore.bit
puts "SUCCESS: Bitstream written to neurocore.bit"
