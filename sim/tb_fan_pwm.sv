`timescale 1ns/1ps
`default_nettype none
// tb_fan_pwm : checks the duty of fan_pwm in automatic and software mode.
// Small clock numbers keep it fast: 100 clocks per slot, 10_000 per period.
module tb_fan_pwm;
    localparam integer CLK_HZ = 1_000_000, PWM_HZ = 100, STEP_S = 1;
    localparam integer PERIOD = CLK_HZ / PWM_HZ;          // clocks per PWM period

    reg         clk = 0, rst = 1;
    reg  [31:0] ctrl = 0;
    wire        fan_en_b;
    wire [6:0]  duty;
    integer     errors = 0;

    fan_pwm #(.CLK_HZ(CLK_HZ), .PWM_HZ(PWM_HZ), .STEP_S(STEP_S)) dut (
        .clk(clk), .rst(rst), .ctrl(ctrl), .fan_en_b(fan_en_b), .duty_o(duty));

    always #5 clk = ~clk;

    // Fraction of one PWM period with the fan on (fan_en_b low), in percent.
    task automatic measure(input integer expect_pct, input string what);
        integer i, on;
        begin
            @(posedge clk);
            while (!(dut.slot == 0 && dut.slot_cnt == 0)) @(posedge clk);
            @(posedge clk);                                  // output is registered
            on = 0;
            for (i = 0; i < PERIOD; i = i + 1) begin
                if (!fan_en_b) on = on + 1;
                @(posedge clk);
            end
            if (on * 100 / PERIOD != expect_pct) begin
                $display("ERROR: %0s: fan on %0d %% of the period, expected %0d %%", what, on * 100 / PERIOD, expect_pct);
                errors = errors + 1;
            end else
                $display("ok: %0s: %0d %%", what, expect_pct);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst = 0;
        measure(100, "auto step 0");
        repeat (PWM_HZ * STEP_S * PERIOD) @(posedge clk);
        measure(75, "auto step 1");
        repeat (PWM_HZ * STEP_S * PERIOD) @(posedge clk);
        measure(50, "auto step 2");
        repeat (PWM_HZ * STEP_S * PERIOD) @(posedge clk);
        measure(25, "auto step 3");
        ctrl = 32'h8000_0000 | 32'd40;
        measure(40, "software 40");
        ctrl = 32'h8000_0000 | 32'd0;
        measure(0, "software 0");
        ctrl = 32'h8000_0000 | 32'd127;
        measure(100, "software 127 (clamped)");
        if (errors == 0) $display("PASS tb_fan_pwm");
        else             $display("FAIL tb_fan_pwm: %0d error(s)", errors);
        $finish;
    end
endmodule
`default_nettype wire
