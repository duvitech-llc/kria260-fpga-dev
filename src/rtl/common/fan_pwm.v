`default_nettype none
// -----------------------------------------------------------------------------
// fan_pwm : PWM for the KV260 fan (fan_en_b, active low), all in the fabric.
//
// Without software it ramps by itself: 100 -> 75 -> 50 -> 25 % duty, one step
// every STEP_S seconds, then again from 100 %. Software takes over by setting
// ctrl[31]; the duty is then ctrl[6:0] in percent (values above 100 = 100).
//
// The PWM runs at PWM_HZ (100 Hz). Keep it slow: the carrier drives the fan
// MOSFET gate through a 10k pull-up, so its edges take about 5 us.
//
// duty_o reports the duty in use, for software and for simulation.
// -----------------------------------------------------------------------------
module fan_pwm #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer PWM_HZ = 100,
    parameter integer STEP_S = 8
) (
    input  wire        clk,
    input  wire        rst,        // synchronous, active high
    input  wire [31:0] ctrl,       // [31] software control, [6:0] duty in %
    output reg         fan_en_b,   // low = fan on
    output wire [6:0]  duty_o
);
    // One "slot" is 1/100 of a PWM period; the duty is a number of slots.
    localparam integer SLOT_CLKS = CLK_HZ / (PWM_HZ * 100);
    localparam integer STEP_PER  = PWM_HZ * STEP_S;          // PWM periods per ramp step

    localparam integer SW = $clog2(SLOT_CLKS);
    localparam integer PW = $clog2(STEP_PER);
    localparam [SW-1:0] SLOT_LAST = SLOT_CLKS[SW-1:0] - 1'b1;
    localparam [PW-1:0] PER_LAST  = STEP_PER[PW-1:0] - 1'b1;

    reg [SW-1:0] slot_cnt;
    reg [6:0]    slot;       // 0..99 within the period
    reg [PW-1:0] per_cnt;
    reg [1:0]    step;          // 0..3 = 100, 75, 50, 25 %

    reg  [6:0] auto_duty;
    always @(*) begin
        case (step)
            2'd0:    auto_duty = 7'd100;
            2'd1:    auto_duty = 7'd75;
            2'd2:    auto_duty = 7'd50;
            default: auto_duty = 7'd25;
        endcase
    end

    wire [6:0] sw_duty = (ctrl[6:0] > 7'd100) ? 7'd100 : ctrl[6:0];
    assign duty_o = ctrl[31] ? sw_duty : auto_duty;

    wire unused_ok = &{1'b0, ctrl[30:7]};   // reserved control bits

    always @(posedge clk) begin
        if (rst) begin
            slot_cnt <= 0;
            slot     <= 7'd0;
            per_cnt  <= 0;
            step     <= 2'd0;
            fan_en_b <= 1'b0;                      // fan on while in reset
        end else begin
            if (slot_cnt == SLOT_LAST) begin
                slot_cnt <= 0;
                if (slot == 7'd99) begin
                    slot <= 7'd0;
                    if (per_cnt == PER_LAST) begin
                        per_cnt <= 0;
                        step    <= step + 2'd1;
                    end else begin
                        per_cnt <= per_cnt + 1'b1;
                    end
                end else begin
                    slot <= slot + 7'd1;
                end
            end else begin
                slot_cnt <= slot_cnt + 1'b1;
            end
            fan_en_b <= ~(slot < duty_o);          // on (low) for duty_o slots
        end
    end
endmodule

`default_nettype wire
