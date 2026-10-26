#!/usr/bin/env bash
# Lint the RTL with Verilator and run the self-checking testbenches with
# Icarus Verilog. No Vivado needed.
#   Verilator: oss-cad-suite (lint only; no C++ compiler is needed)
#   Icarus:    iverilog / vvp on the PATH
# The block design is replaced by sim/system_stub.v.
set -euo pipefail
cd "$(dirname "$0")/.."
V=${VERILATOR:-$(command -v verilator_bin.exe || command -v verilator_bin || command -v verilator || echo /c/oss-cad-suite/bin/verilator_bin.exe)}
if [ -z "${VERILATOR_ROOT:-}" ] && [ -d /c/oss-cad-suite/share/verilator ]; then export VERILATOR_ROOT=C:/oss-cad-suite/share/verilator; fi
OUT=${SIM_OUT:-sim/build}
mkdir -p "$OUT"

RTL="src/rtl/top.v src/rtl/common/fan_pwm.v src/rtl/common/reset_sync.v src/rtl/video/dp_tpg.v"
LINT="--lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module top"

lint() {  # name, defines...
    local name=$1; shift
    echo "== lint ($name)"
    "$V" $LINT "$@" $RTL sim/system_stub.v
}
lint "default"            -DUSE_PMOD
lint "pmod=0"
lint "fan=rtl"            -DUSE_PMOD -DUSE_FAN_RTL
lint "pmod=0 fan=rtl"     -DUSE_FAN_RTL
lint "dp=1"               -DUSE_PMOD -DUSE_DP
lint "fan=rtl dp=1"       -DUSE_PMOD -DUSE_FAN_RTL -DUSE_DP
lint "iic=1"              -DUSE_PMOD -DUSE_IIC
lint "cam=rpi"            -DUSE_PMOD -DUSE_IIC -DUSE_CAM -DCAM_LANES=2
lint "all"                -DUSE_PMOD -DUSE_FAN_RTL -DUSE_DP -DUSE_IIC -DUSE_CAM -DCAM_LANES=4

run() {  # testbench, sources...
    local tb=$1; shift
    echo "== sim: $tb"
    iverilog -g2012 -Wall -s "$tb" -o "$OUT/$tb.vvp" "sim/$tb.sv" "$@" > "$OUT/$tb.build.log" 2>&1 \
        || { cat "$OUT/$tb.build.log"; exit 1; }
    vvp -n "$OUT/$tb.vvp" | tee "$OUT/$tb.out"
    grep -q "^PASS" "$OUT/$tb.out" || { echo "SIMULATION FAILED: $tb"; exit 1; }
}
run tb_fan_pwm src/rtl/common/fan_pwm.v
run tb_dp_tpg  src/rtl/video/dp_tpg.v

echo "ALL SIMULATIONS PASSED"
