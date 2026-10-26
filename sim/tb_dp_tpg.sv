`timescale 1ns/1ps
`default_nettype none
// tb_dp_tpg : checks dp_tpg timing (line/frame length, sync widths, active
// pixels per frame) and the pixel bus packing, on a small 64x16 frame.
module tb_dp_tpg;
    localparam integer HA = 64, HFP = 4, HS = 6, HBP = 10;
    localparam integer VA = 16, VFP = 2, VS = 3, VBP = 4;
    localparam integer HT = HA + HFP + HS + HBP, VT = VA + VFP + VS + VBP;

    reg         clk = 0, rst = 1;
    reg  [31:0] ctrl = 0;
    wire [35:0] pixel;
    wire        hsync, vsync, de;
    wire [15:0] frames;
    integer     errors = 0;

    dp_tpg #(.H_ACTIVE(HA), .H_FP(HFP), .H_SYNC(HS), .H_BP(HBP),
             .V_ACTIVE(VA), .V_FP(VFP), .V_SYNC(VS), .V_BP(VBP)) dut (
        .clk(clk), .rst(rst), .ctrl(ctrl), .pixel(pixel),
        .hsync(hsync), .vsync(vsync), .de(de), .frame_cnt(frames));

    always #5 clk = ~clk;
    reg de_prev = 0;
    always @(posedge clk) de_prev <= de;

    task automatic check(input longint got, input longint want, input string what);
        if (got != want) begin
            $display("ERROR: %0s = 0x%0h, expected 0x%0h", what, got, want);
            errors = errors + 1;
        end else
            $display("ok: %0s = 0x%0h", what, got);
    endtask

    // Measure one whole frame, starting at the first active pixel.
    task automatic measure_frame(output integer clocks, output integer active,
                                 output integer hs_clocks, output integer vs_clocks);
        integer n;
        begin
            while (!(de && !de_prev)) @(posedge clk);
            clocks = 0; active = 0; hs_clocks = 0; vs_clocks = 0;
            for (n = 0; n < HT * VT; n = n + 1) begin
                clocks = clocks + 1;
                if (de)    active    = active + 1;
                if (hsync) hs_clocks = hs_clocks + 1;
                if (vsync) vs_clocks = vs_clocks + 1;
                @(posedge clk);
            end
        end
    endtask

    integer clocks, active, hsc, vsc;
    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        measure_frame(clocks, active, hsc, vsc);
        check(active, HA * VA, "active pixels per frame");
        check(hsc, HS * VT, "hsync clocks per frame");
        check(vsc, VS * HT, "vsync clocks per frame");

        // Solid colour, then the same with red and blue swapped.
        ctrl = {24'h12_34_56, 8'h01};
        repeat (HT * VT) @(posedge clk);
        while (!de) @(posedge clk);
        check(pixel, {8'h12, 4'h0, 8'h34, 4'h0, 8'h56, 4'h0}, "solid 0x123456 on the pixel bus");
        ctrl = {24'h12_34_56, 8'h11};
        repeat (HT * VT) @(posedge clk);
        while (!de) @(posedge clk);
        check(pixel, {8'h56, 4'h0, 8'h34, 4'h0, 8'h12, 4'h0}, "solid with red/blue swapped");

        // Colour bars: first pixel of a line is white, last bar is black.
        ctrl = 32'h0;
        repeat (HT * VT) @(posedge clk);
        while (!(de && !de_prev)) @(posedge clk);
        repeat (2) @(posedge clk);
        check(pixel, 36'hFF0_FF0_FF0, "bar 0 is white");
        repeat (HA - 6) @(posedge clk);
        check(pixel, 36'h0, "bar 7 is black");

        check(frames > 3, 1, "frame counter advances");
        if (errors == 0) $display("PASS tb_dp_tpg");
        else             $display("FAIL tb_dp_tpg: %0d error(s)", errors);
        $finish;
    end
endmodule
`default_nettype wire
