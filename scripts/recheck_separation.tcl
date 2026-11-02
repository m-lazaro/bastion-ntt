#############################################################
# Rerun the separation checks on a routed checkpoint, without
# re-implementing the design:
#   vivado -mode batch -source scripts/recheck_separation.tcl \
#          -tclargs <routed.dcp> <report file>
#############################################################
set dcp [lindex $argv 0]
set rpt [lindex $argv 1]
open_checkpoint $dcp
source [file join [file dirname [file normalize [info script]]] separation_checks.tcl]
run_separation_checks $rpt
