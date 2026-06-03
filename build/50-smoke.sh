#!/usr/bin/env bash
# =============================================================================
# 50-smoke.sh — run the 4 Aurora flows against a bundle and report PASS/FAIL.
# This is the gate for every trim block and every release.
#
#   bash build/50-smoke.sh <bundle-root>     # e.g. dist/msys
#
# Flows: iverilog sim · yosys hierarchy → JSON · cocotb-icarus · cocotb-verilator.
# Exits non-zero if any flow fails.
# =============================================================================
set -uo pipefail
B="${1:?usage: 50-smoke.sh <bundle-root>}"
W="$(mktemp -d)"; WM="$(cygpath -m "$W" 2>/dev/null || echo "$W")"; BM="$(cygpath -m "$B" 2>/dev/null || echo "$B")"
PY="$B/mingw64/bin/python.exe"
pass=0; fail=0
ck(){ if echo "$2" | grep -q "$3"; then echo "  PASS  $1"; pass=$((pass+1));
      else echo "  FAIL  $1"; fail=$((fail+1));
           printf -- '----- %s output -----\n%s\n----------------------\n' "$1" "$(echo "$2" | tail -30)"; fi; }

cat > "$W/leaf.v" <<'V'
module leaf(input a,input b,output y); assign y=a&b; endmodule
V
cat > "$W/top.v" <<'V'
module top(input x,input y,input z,output w); wire t; leaf u1(.a(x),.b(y),.y(t)); leaf u2(.a(t),.b(z),.y(w)); endmodule
V
cat > "$W/dff.v" <<'V'
module dff(input clk,input d,output reg q); always @(posedge clk) q<=d; endmodule
V
cat > "$W/dff_tb.v" <<'V'
module tb; reg clk=0,d=0; wire q; dff u(clk,d,q); always #5 clk=~clk;
initial begin d=1; #10; if(q!==1) $display("IVFAIL"); else $display("IVOK"); $finish; end endmodule
V
cat > "$W/test_dff.py" <<'PY'
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
@cocotb.test()
async def t(dut):
    cocotb.start_soon(Clock(dut.clk,10,unit="ns").start())
    dut.d.value=1; await RisingEdge(dut.clk); await Timer(1,unit="ns"); assert int(dut.q.value)==1
PY
cat > "$W/run_cocotb.py" <<'PY'
import os
from pathlib import Path
from cocotb_tools.runner import get_runner
h=Path(__file__).parent; sim=os.environ["SIM"]; bd=str(h/("sb_"+sim))
r=get_runner(sim)
r.build(sources=[str(h/"dff.v")],hdl_toplevel="dff",build_dir=bd,build_args=(["-g2012"] if sim=="icarus" else []),timescale=("1ns","1ps"),always=True,waves=True)
r.test(hdl_toplevel="dff",test_module="test_dff",build_dir=bd,test_dir=str(h),waves=True)
print(f"COCOTB_{sim}_OK")
PY

# 1. iverilog
PATH="$B/mingw64/bin:$PATH" "$B/mingw64/bin/iverilog.exe" -o "$WM/sim.vvp" "$WM/dff.v" "$WM/dff_tb.v" >/dev/null 2>&1
O=$(PATH="$B/mingw64/bin:$PATH" "$B/mingw64/bin/vvp.exe" "$WM/sim.vvp" 2>&1); ck "iverilog sim" "$O" "IVOK"

# 2. yosys
cat > "$W/h.ys" <<EOF
read_verilog -sv "$WM/leaf.v"
read_verilog -sv "$WM/top.v"
hierarchy -top top
proc
write_json "$WM/hier.json"
EOF
PATH="$B/mingw64/bin:$PATH" "$B/mingw64/bin/yosys.exe" -q -s "$WM/h.ys" >/dev/null 2>&1
[ -s "$W/hier.json" ] && ck "yosys hierarchy" "ok" "ok" || ck "yosys hierarchy" "no" "ok"

# 3+4. cocotb icarus + verilator (same bundle Python, both VPIs)
for sim in icarus verilator; do
  O=$( cd "$W" && env SIM=$sim TOPLEVEL_LANG=verilog WAVES=1 PYTHONHOME="$BM/mingw64" \
        PATH="$B/mingw64/bin:$B/usr/bin" "$PY" run_cocotb.py 2>&1 )
  ck "cocotb-$sim" "$O" "COCOTB_${sim}_OK"
done

rm -rf "$W"
echo "  --- PASS=$pass FAIL=$fail ---"
[ "$fail" = 0 ]
