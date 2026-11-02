#############################################################
# BASTION — build + timing sweep for one configuration
#############################################################
# Run from bash (NOT pasted into a terminal by itself):
#     vivado -mode batch -source build_config.tcl -tclargs bastion 5.200
#
# Arg 1 = folder name inside rtl_root   (baseline_a, baseline_b,
#                                        baseline_c, bastion, bastion_nodt,
#                                        bastion_stag, bastion_seq)
# Arg 2 = clock period in ns            (e.g. 5.200)
#
# For the cores with two share domains (bastion, bastion_nodt,
# bastion_stag) the run ends with the separation checks of
# separation_checks.tcl (report: build/reports/sep_<cfg>_<period>.rpt).
# Every run also writes a timing-simulation netlist and its SDF for the
# post-route simulation (build/timesim/).
#############################################################

set cfg    [lindex $argv 0]
set period [lindex $argv 1]

if {$cfg eq "" || $period eq ""} {
    puts "ERROR: usage -> vivado -mode batch -source build_config.tcl -tclargs <folder> <period_ns>"
    exit 1
}

# ---- paths -------------------------------------------------
# Paths are resolved relative to this script's location, so the repository
# can be cloned and built anywhere.
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]
set rtl_root   $repo_root/rtl
set proj_root  $repo_root/build
set part      xc7a200tfbg676-2
# ------------------------------------------------------------

set srcdir  $rtl_root/$cfg
set projdir $proj_root/${cfg}_${period}

if {![file isdirectory $srcdir]} {
    puts "ERROR: source folder not found: $srcdir"
    exit 1
}

file mkdir $proj_root
if {[file exists $projdir]} { file delete -force $projdir }

create_project ntt_$cfg $projdir -part $part -force

# ---- design sources ----------------------------------------
# Testbenches (tb_*) and simulation monitors (chk_*) are not design sources.
set dsrc {}
foreach v [glob -nocomplain $srcdir/*.v] {
    set tail [file tail $v]
    if {[string match "*tb_*" $tail] || [string match "chk_*" $tail]} { continue }
    lappend dsrc $v
}
if {[llength $dsrc] == 0} {
    puts "ERROR: no design sources found in $srcdir"
    exit 1
}
add_files -norecurse $dsrc

set_property top ntt_top [current_fileset]
update_compile_order -fileset sources_1

# ---- simulation sources ------------------------------------
if {[file exists $srcdir/tb_ntt_top.v]} {
    add_files -fileset sim_1 -norecurse $srcdir/tb_ntt_top.v
    foreach h [glob -nocomplain $srcdir/*.hex] {
        add_files -fileset sim_1 -norecurse $h
    }
    set_property top tb_ntt_top [get_filesets sim_1]
    update_compile_order -fileset sim_1
}

# ---- constraints, generated fresh at the requested period ---
# The optional interface ports are detected from the RTL, not from the
# folder name. Every interface input and output is a false path, so
# f_max is core-only and comparable across configurations.
set fh_top [open $srcdir/ntt_top.v r]
set toptxt [read $fh_top]
close $fh_top
regsub -all {//[^\n]*} $toptxt {} toptxt
set has_sel   [string match "*ext_share_sel*" $toptxt]
set has_re    [string match "*ext_re*"        $toptxt]
set has_sched [string match "*order_rand*"    $toptxt]
set two_doms  [string match "*rd1_q*"         $toptxt]

set in_ports [list start ext_we {ext_addr_w[*]} {ext_data_w[*]} {ext_addr_r[*]}]
if {$has_sel}   { lappend in_ports ext_share_sel }
if {$has_re}    { lappend in_ports ext_re }
if {$has_sched} { lappend in_ports {delta[*]} order_rand }

set xdc $projdir/ntt_${cfg}.xdc
set fh  [open $xdc w]
puts $fh "create_clock -name sys_clk -period $period -waveform {0.000 [expr {$period/2.0}]} \[get_ports clk\]"
puts $fh "set_false_path -from \[get_ports rst\]"
puts $fh "set_false_path -from \[get_ports {[join $in_ports { }]}\]"
puts $fh "set_false_path -to \[get_ports {done ext_data_r\[*\]}\]"
close $fh
add_files -fileset constrs_1 -norecurse $xdc

# ---- synthesise + implement --------------------------------
reset_run synth_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
open_run impl_1

set rpt $proj_root/reports
file mkdir $rpt
report_utilization               -file $rpt/util_${cfg}_${period}.rpt
report_utilization -hierarchical -file $rpt/util_hier_${cfg}_${period}.rpt
report_timing_summary            -file $rpt/timing_${cfg}_${period}.rpt
report_timing -max_paths 1       -file $rpt/critpath_${cfg}_${period}.rpt

# ---- timing-simulation netlist for the post-route simulation ----
set tsim $proj_root/timesim
file mkdir $tsim
write_verilog -force -mode timesim -sdf_anno true $tsim/ntt_top_${cfg}_${period}.v
write_sdf     -force $tsim/ntt_top_${cfg}_${period}.sdf

# ---- headline numbers --------------------------------------
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "=========================================================="
puts " CONFIG      : $cfg"
puts " Tclk        : $period ns"
puts " WNS         : $wns ns"
if {$wns >= 0} {
    puts " fmax        : [format %.1f [expr {1000.0/($period - $wns)}]] MHz   TIMING MET"
} else {
    puts " fmax        : ---   TIMING FAILED, raise the period"
}
set fh_u [open $rpt/util_${cfg}_${period}.rpt r]
foreach line [split [read $fh_u] "\n"] {
    if {[regexp {\|\s+(Slice LUTs|LUT as Logic|LUT as Memory|Slice Registers|Register as Flip Flop|Slice|DSPs|Block RAM Tile)\s} $line]} {
        puts " $line"
    }
}
close $fh_u

# ---- separation checks (two-domain cores only) --------------
if {$two_doms} {
    source $script_dir/separation_checks.tcl
    run_separation_checks $rpt/sep_${cfg}_${period}.rpt
}
puts "=========================================================="
