#############################################################
# BASTION — structural separation checks on the routed netlist
#############################################################
# Sourced by build_config.tcl after implementation, for the cores with
# two share domains (bastion, bastion_nodt, bastion_stag). Can also be
# sourced by hand in a Vivado session with the routed design open:
#     source scripts/separation_checks.tcl
#     run_separation_checks build/reports/sep_bastion_5.200.rpt
#
# Domain 0 = cells under s0_even, s0_odd, bf0, bf1 and the registers
# rd0_q; domain 1 = s1_even, s1_odd, bf2, bf3 and rd1_q.
#
#   Q1  timing paths from sequential cells of domain 0 to those of
#       domain 1, and from domain 1 to domain 0                 -> 0
#   Q2  timing paths from either domain to sequential cells outside
#       both domains (controller, LFSR, ROM, read enables)      -> 0
#   Q3  primitives whose combinational input cone holds sequential
#       cells of both domains. Each is EXPECTED when the only domain
#       cells in its cone are the read registers rd0_q and rd1_q (the
#       output multiplexer and the buffers it drives), UNEXPECTED
#       otherwise                                    -> no UNEXPECTED
#   Q4  check_timing: no combinational loops, no latch loops, no
#       unconstrained internal endpoints, no register without a clock
#############################################################

# Cells of list a whose name is not in list b. Set differences are taken in
# Tcl: a negated filter such as "!(NAME =~ x || ...)" matches nothing in
# Vivado 2022.1, which would make Q2 and the classification of Q3 vacuous.
proc cells_minus {a b} {
    array set inb {}
    foreach c $b { set inb([get_property NAME $c]) 1 }
    set r {}
    foreach c $a { if {![info exists inb([get_property NAME $c])]} { lappend r $c } }
    return $r
}

proc run_separation_checks {rpt_file} {
    set p0 {NAME =~ s0_* || NAME =~ bf0/* || NAME =~ bf1/* || NAME =~ rd0_q_reg*}
    set p1 {NAME =~ s1_* || NAME =~ bf2/* || NAME =~ bf3/* || NAME =~ rd1_q_reg*}
    set rd {NAME =~ rd0_q_reg* || NAME =~ rd1_q_reg*}

    set fh [open $rpt_file w]
    puts $fh "BASTION separation checks"
    puts $fh "domain 0 filter: $p0"
    puts $fh "domain 1 filter: $p1"
    puts $fh ""

    # ---- sequential cells per domain -------------------------
    set c0 [get_cells -quiet -hierarchical -filter "IS_SEQUENTIAL && ($p0)"]
    set c1 [get_cells -quiet -hierarchical -filter "IS_SEQUENTIAL && ($p1)"]
    set call [get_cells -quiet -hierarchical -filter {IS_SEQUENTIAL}]
    set c2 [cells_minus [cells_minus $call $c0] $c1]
    set crd [get_cells -quiet -hierarchical -filter $rd]
    puts $fh "sequential cells: domain 0 = [llength $c0], domain 1 = [llength $c1], outside = [llength $c2], total = [llength $call]"
    if {[llength $c0] == 0 || [llength $c1] == 0} {
        puts $fh "ERROR: a domain has no sequential cells; check the instance names."
        close $fh
        puts " SEPARATION  : ERROR, empty domain (see $rpt_file)"
        return
    }

    # ---- Q1: domain to domain ---------------------------------
    set q1a [get_timing_paths -quiet -from $c0 -to $c1 -max_paths 1000 -nworst 1]
    set q1b [get_timing_paths -quiet -from $c1 -to $c0 -max_paths 1000 -nworst 1]
    puts $fh "Q1 paths domain 0 to domain 1: [llength $q1a]"
    foreach p $q1a {
        puts $fh "   [get_property STARTPOINT_PIN $p]  to  [get_property ENDPOINT_PIN $p]"
    }
    puts $fh "Q1 paths domain 1 to domain 0: [llength $q1b]"
    foreach p $q1b {
        puts $fh "   [get_property STARTPOINT_PIN $p]  to  [get_property ENDPOINT_PIN $p]"
    }

    # ---- Q2: domains to sequential cells outside them ---------
    set q2a {}
    set q2b {}
    if {[llength $c2] > 0} {
        set q2a [get_timing_paths -quiet -from $c0 -to $c2 -max_paths 1000 -nworst 1]
        set q2b [get_timing_paths -quiet -from $c1 -to $c2 -max_paths 1000 -nworst 1]
    }
    set n_q2 [expr {[llength $q2a] + [llength $q2b]}]
    puts $fh "Q2 paths from a domain to cells outside both: $n_q2"
    foreach p $q2a {
        puts $fh "   [get_property STARTPOINT_PIN $p]  to  [get_property ENDPOINT_PIN $p]"
    }
    foreach p $q2b {
        puts $fh "   [get_property STARTPOINT_PIN $p]  to  [get_property ENDPOINT_PIN $p]"
    }

    # ---- Q3: primitives whose input cone holds both domains ---
    set n_exp 0
    set unexp {}
    set expected_cells {}
    foreach c [get_cells -quiet -hierarchical -filter {IS_PRIMITIVE}] {
        set ins [get_pins -quiet -of_objects $c -filter {DIRECTION == IN}]
        if {[llength $ins] == 0} { continue }
        set src [all_fanin -quiet -flat -only_cells -startpoints_only $ins]
        if {[llength $src] == 0} { continue }
        set h0 [filter -quiet $src $p0]
        set h1 [filter -quiet $src $p1]
        if {[llength $h0] == 0 || [llength $h1] == 0} { continue }
        set x0 [cells_minus $h0 $crd]
        set x1 [cells_minus $h1 $crd]
        if {[llength $x0] == 0 && [llength $x1] == 0} {
            incr n_exp
            lappend expected_cells "$c ([get_property REF_NAME $c])"
        } else {
            lappend unexp "$c ([get_property REF_NAME $c]): domain-0 cells [llength $h0], domain-1 cells [llength $h1], not read registers: [concat $x0 $x1]"
        }
    }
    puts $fh "Q3 mixed-cone primitives: EXPECTED (read registers only) = $n_exp, UNEXPECTED = [llength $unexp]"
    foreach e $expected_cells { puts $fh "   EXPECTED   $e" }
    foreach u $unexp          { puts $fh "   UNEXPECTED $u" }

    # ---- Q4: design-wide timing check -------------------------
    puts $fh ""
    puts $fh "Q4 check_timing (verbose) follows."
    close $fh
    check_timing -verbose -file $rpt_file -append

    # ---- summary ---------------------------------------------
    set ok1 [expr {[llength $q1a] == 0 && [llength $q1b] == 0}]
    set ok2 [expr {$n_q2 == 0}]
    set ok3 [expr {[llength $unexp] == 0}]
    puts " SEPARATION  : Q1 [expr {$ok1 ? "PASS" : "FAIL"}] ([llength $q1a] + [llength $q1b] paths)"
    puts "               Q2 [expr {$ok2 ? "PASS" : "FAIL"}] ($n_q2 paths)"
    puts "               Q3 [expr {$ok3 ? "PASS" : "FAIL"}] ($n_exp expected, [llength $unexp] unexpected)"
    puts "               Q4 see the check_timing section of $rpt_file"
}
