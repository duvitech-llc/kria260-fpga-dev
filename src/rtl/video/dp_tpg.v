`default_nettype none
// -----------------------------------------------------------------------------
// dp_tpg : video timing + test pattern for the PS DisplayPort live-video input.
//
// Runs on the PS video clock (dp_video_ref_clk, 74.25 MHz for 1280x720 at
// 60 Hz) and drives dp_live_video_in_{pixel1,hsync,vsync,de}. The DP
// controller sends it to J6 (DisplayPort) and, through the carrier's
// converter, to J5 (HDMI).
//
// Control word (from the processor, any clock; synchronised here):
//   [1:0]  pattern: 0 colour bars, 1 solid colour [31:8], 2 colour bars with
//          a moving white square (shows the picture is live), 3 grey ramp
//   [4]    swap the red and blue fields of the pixel bus
//   [31:8] solid colour, 0xRRGGBB
// frame_cnt counts frames (vsync), in the video clock domain; the processor
// reads it through a synchroniser.
//
// Pixel bus: 3 x 12-bit fields, 8-bit colour MSB-aligned in each field:
//   pixel[35:24] = red, [23:12] = green, [11:0] = blue (swap with ctrl[4]).
// -----------------------------------------------------------------------------
module dp_tpg #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FP     = 110,
    parameter integer H_SYNC   = 40,
    parameter integer H_BP     = 220,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FP     = 5,
    parameter integer V_SYNC   = 5,
    parameter integer V_BP     = 20
) (
    input  wire        clk,         // pixel clock
    input  wire        rst,         // synchronous to clk, active high
    input  wire [31:0] ctrl,        // asynchronous, quasi-static
    output reg  [35:0] pixel,
    output reg         hsync,       // active high
    output reg         vsync,       // active high
    output reg         de,
    output reg  [15:0] frame_cnt
);
    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    // 12-bit copies of the timing numbers, so every comparison is 12 bits wide.
    localparam [11:0] HA   = H_ACTIVE[11:0];
    localparam [11:0] VA   = V_ACTIVE[11:0];
    localparam [11:0] HS0  = HA + H_FP[11:0];
    localparam [11:0] HS1  = HS0 + H_SYNC[11:0];
    localparam [11:0] VS0  = VA + V_FP[11:0];
    localparam [11:0] VS1  = VS0 + V_SYNC[11:0];
    localparam [11:0] HL   = H_TOTAL[11:0] - 12'd1;
    localparam [11:0] VL   = V_TOTAL[11:0] - 12'd1;
    localparam [11:0] BOX  = 12'd64;
    localparam [11:0] BARW = H_ACTIVE[14:3];          // width of one of 8 bars

    // ---- control word into the pixel clock domain ----
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_m, ctrl_s;
    always @(posedge clk) begin
        ctrl_m <= ctrl;
        ctrl_s <= ctrl_m;
    end

    // ---- timing ----
    reg [11:0] hc, vc;
    always @(posedge clk) begin
        if (rst) begin
            hc <= 12'd0;
            vc <= 12'd0;
        end else if (hc == HL) begin
            hc <= 12'd0;
            vc <= (vc == VL) ? 12'd0 : vc + 12'd1;
        end else begin
            hc <= hc + 12'd1;
        end
    end

    wire active    = (hc < HA) && (vc < VA);
    wire hs        = (hc >= HS0) && (hc < HS1);
    wire vs        = (vc >= VS0) && (vc < VS1);
    wire frame_end = (hc == HL) && (vc == VL);

    // ---- moving square: bounces around the active area ----
    reg [11:0] bx, by;
    reg        bdx, bdy;    // 1 = moving right / down
    always @(posedge clk) begin
        if (rst) begin
            bx <= 12'd0;  by <= 12'd0;  bdx <= 1'b1;  bdy <= 1'b1;
            frame_cnt <= 16'd0;
        end else if (frame_end) begin
            frame_cnt <= frame_cnt + 16'd1;
            if (bdx) begin
                if (bx >= HA - BOX - 12'd4) bdx <= 1'b0; else bx <= bx + 12'd4;
            end else begin
                if (bx < 12'd4) bdx <= 1'b1; else bx <= bx - 12'd4;
            end
            if (bdy) begin
                if (by >= VA - BOX - 12'd4) bdy <= 1'b0; else by <= by + 12'd4;
            end else begin
                if (by < 12'd4) bdy <= 1'b1; else by <= by - 12'd4;
            end
        end
    end

    // ---- pattern ----
    // Eight vertical bars: white, yellow, cyan, green, magenta, red, blue, black.
    // bar_idx counts bars along the line.
    reg  [23:0] bar;
    reg  [2:0]  bar_idx;
    reg  [11:0] bar_col;
    always @(posedge clk) begin
        if (rst || hc == HL) begin
            bar_idx <= 3'd0;
            bar_col <= 12'd0;
        end else if (bar_col == BARW - 12'd1) begin
            bar_idx <= bar_idx + 3'd1;
            bar_col <= 12'd0;
        end else begin
            bar_col <= bar_col + 12'd1;
        end
    end
    always @(*) begin
        case (bar_idx)
            3'd0:    bar = 24'hFFFFFF;
            3'd1:    bar = 24'hFFFF00;
            3'd2:    bar = 24'h00FFFF;
            3'd3:    bar = 24'h00FF00;
            3'd4:    bar = 24'hFF00FF;
            3'd5:    bar = 24'hFF0000;
            3'd6:    bar = 24'h0000FF;
            default: bar = 24'h000000;
        endcase
    end

    wire in_box = (hc >= bx) && (hc < bx + BOX) && (vc >= by) && (vc < by + BOX);
    wire [7:0] ramp = hc[10:3];      // 0..159 across 1280 pixels, scaled below

    reg [23:0] rgb;
    always @(*) begin
        case (ctrl_s[1:0])
            2'd0:    rgb = bar;
            2'd1:    rgb = ctrl_s[31:8];
            2'd2:    rgb = in_box ? 24'hFFFFFF : bar;
            default: rgb = {3{ramp + (ramp >> 2) + (ramp >> 4)}};   // ~0..255
        endcase
    end

    wire unused_ok = &{1'b0, ctrl_s[7:5], ctrl_s[3:2]};   // reserved

    wire [7:0] r = ctrl_s[4] ? rgb[7:0]   : rgb[23:16];
    wire [7:0] g = rgb[15:8];
    wire [7:0] b = ctrl_s[4] ? rgb[23:16] : rgb[7:0];

    always @(posedge clk) begin
        if (rst) begin
            pixel <= 36'd0;
            hsync <= 1'b0;
            vsync <= 1'b0;
            de    <= 1'b0;
        end else begin
            pixel <= active ? {r, 4'h0, g, 4'h0, b, 4'h0} : 36'd0;
            hsync <= hs;
            vsync <= vs;
            de    <= active;
        end
    end
endmodule

`default_nettype wire
