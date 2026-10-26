# ============================================================
# KV260: settings and helpers shared by all Vivado scripts
# ============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ".."]]

set proj_name "kv260_base"
set proj_dir  [file join $repo_dir "vivado"]
set part      "xck26-sfvc784-2LV-c"
set bd_name   "system"

# ---- Options: key=value words after -tclargs (or `set argv {...}`) -----------
#   pmod=1|0   PMOD J2 as 8 processor GPIO pins, direction per pin   (default 1)
#   fan=ps|rtl fan (A12) PWM source: ps = PS TTC0 waveform via EMIO, set by
#              software; rtl = src/rtl/common/fan_pwm.v in the fabric, ramps
#              on its own, software may take over               (default ps)
#   irq=1|0    PL timer (axi_timer) interrupting the PS through pl_ps_irq0
#                                                                (default 0)
#   dma=1|0    AXI CDMA: PL DMA engine copying DDR to DDR through S_AXI_HP1_FPD,
#              with a completion interrupt                       (default 0)
#   dp=1|0     RTL test pattern (src/rtl/video/dp_tpg.v) into the PS DisplayPort
#              live-video input, 1280x720 at 60 Hz, on J6 (DP) and J5 (HDMI)
#                                                                (default 0)
#   iic=1|0    camera I2C (axi_iic on G11/F10, through the TCA9546 switch to
#              the AP1302 ISP, the IAS sensor and the RPi camera) and the
#              camera control pins (axi_gpio_cam)               (default 0)
#   cam=none|rpi|ias|isp  MIPI CSI-2 camera capture into DDR (tcl/create_cam.tcl):
#              rpi = Raspberry Pi camera on J9, ias = IAS module on J8,
#              isp = IAS module on J7 through the AP1302 ISP. One at a time;
#              turns iic on                                     (default none)
#   cpu=none|mbv  mbv adds a MicroBlaze V (RISC-V) co-processor in the fabric
#              (tcl/create_mbv.tcl): 128 KB memory the A53 loads, a mailbox
#              and interrupts both ways                         (default none)
#   jobs=N     parallel jobs for synthesis/implementation            (default 8)
array set opt {pmod 1 fan ps irq 0 dma 0 dp 0 iic 0 cam none cpu none jobs 8}

proc parse_options {} {
    global opt argv
    if {![info exists argv]} { return }
    # vivado.bat (Windows) splits arguments at '=', so "fan=rtl" can arrive as
    # the two words "fan" "rtl". Accept both forms.
    set words $argv
    while {[llength $words] > 0} {
        set arg   [lindex $words 0]
        set words [lrange $words 1 end]
        if {[regexp {^([a-z0-9_]+)=(.+)$} $arg -> key value]} {
        } elseif {[info exists opt($arg)] && [llength $words] > 0} {
            set key $arg
            set value [lindex $words 0]
            set words [lrange $words 1 end]
        } else {
            error "Bad option '$arg' (expected key=value, e.g. pmod=0 jobs=16)"
        }
        if {![info exists opt($key)]} {
            error "Unknown option '$key'. Known options: [lsort [array names opt]]"
        }
        set opt($key) $value
    }
    if {[lsearch -exact {0 1} $opt(pmod)] < 0} { error "pmod must be 0 or 1, got '$opt(pmod)'" }
    if {[lsearch -exact {ps rtl} $opt(fan)] < 0} { error "fan must be ps or rtl, got '$opt(fan)'" }
    if {[lsearch -exact {none mbv} $opt(cpu)] < 0} { error "cpu must be none or mbv, got '$opt(cpu)'" }
    foreach k {irq dma dp iic} {
        if {[lsearch -exact {0 1} $opt($k)] < 0} { error "$k must be 0 or 1, got '$opt($k)'" }
    }
    if {[lsearch -exact {none rpi ias isp} $opt(cam)] < 0} { error "cam must be none, rpi, ias or isp, got '$opt(cam)'" }
    if {$opt(cam) ne "none"} { set opt(iic) 1 }   ;# the camera is set up over I2C
    if {![string is integer -strict $opt(jobs)] || $opt(jobs) < 1} { error "jobs must be a positive integer" }
}

proc options_string {} {
    global opt
    set s {}
    foreach k [lsort [array names opt]] { if {$k ne "jobs"} { lappend s "$k=$opt($k)" } }
    return [join $s " "]
}

# Newest installed version of an IP, as a VLNV. Avoids hard-coding IP
# versions, which change between Vivado releases.
proc latest_ip {name} {
    set defs [lsort -dictionary [get_ipdefs -all -filter "NAME == $name"]]
    if {[llength $defs] == 0} { error "IP '$name' is not in this Vivado installation's catalog" }
    return [lindex $defs end]
}

# Connect src to dst, replacing whatever dst was connected to.
proc force_connect {src dst} {
    set old [get_bd_nets -quiet -of_objects $dst]
    if {[llength $old] > 0} { disconnect_bd_net $old $dst }
    connect_bd_net $src $dst
}
