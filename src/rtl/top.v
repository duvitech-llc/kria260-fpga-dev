`default_nettype none
// -----------------------------------------------------------------------------
// top : Kria KV260 base design (XCK26-SFVC784-2LV-C on the K26 SoM)
//
// Build options, set by tcl/create_project.tcl as Verilog defines:
//   USE_PMOD     PMOD J2 as 8 processor GPIO pins (axi_gpio_pmod), direction
//                per pin. pmod[0..3] = PMOD pins 1..4 (top row), pmod[4..7] =
//                pins 7..10 (bottom row).
//   USE_FAN_RTL  the fan PWM comes from the fabric (src/rtl/common/fan_pwm.v):
//                it ramps 100/75/50/25 % on its own, 8 s per step, with no
//                program running; software can take over through
//                axi_gpio_fan. Without it the PS TTC0 waveform drives the fan
//                and software sets the speed.
//   USE_DP       1280x720 test pattern from src/rtl/video/dp_tpg.v into the PS
//                DisplayPort controller's live-video input, shown on J6 (DP)
//                and J5 (HDMI) once software has trained the link. Pattern
//                and colours from axi_gpio_dp; the frame counter goes back.
//   USE_IIC      camera I2C (iic_scl/iic_sda, to the TCA9546 switch) and the
//                camera control pins cam_ctrl[3:0] = {rpi_cam_en,
//                ias_xshutdown_b, ap1302_standby, ap1302_rst_b}, all driven
//                by the processor (axi_iic_cam, axi_gpio_cam).
//   USE_CAM      MIPI CSI-2 camera input (CAM_LANES lanes) to the receiver in
//                the block design, which writes frames into DDR
//                (tcl/create_cam.tcl). The camera is chosen with cam=.
//
// fan_en_b (J13 fan, A12) is active low: high = fan off, low or unconfigured
// = fan on.
//
// The KV260 has no PL oscillator, no PL LEDs and no PL buttons. Every PL
// clock comes from the PS (pl_clk = pl_clk0, 100 MHz), so the PS must be
// initialised (tcl/program.tcl runs psu_init) before any of this logic runs.
// -----------------------------------------------------------------------------
module top (
`ifdef USE_PMOD
    inout  wire [7:0] pmod,
`endif
`ifdef USE_IIC
    inout  wire       iic_scl,
    inout  wire       iic_sda,
    output wire [3:0] cam_ctrl,
`endif
`ifdef USE_CAM
    input  wire                    mipi_cam_clk_p,
    input  wire                    mipi_cam_clk_n,
    input  wire [`CAM_LANES-1:0]   mipi_cam_data_p,
    input  wire [`CAM_LANES-1:0]   mipi_cam_data_n,
`endif
    output wire       fan_en_b
);

    wire pl_clk;    // 100 MHz from the PS
    wire pl_rst;    // synchronous to pl_clk, active high

`ifdef USE_FAN_RTL
    wire [31:0] fan_ctrl;
    wire [6:0]  fan_duty;

    fan_pwm u_fan (
        .clk      (pl_clk),
        .rst      (pl_rst),
        .ctrl     (fan_ctrl),
        .fan_en_b (fan_en_b),
        .duty_o   (fan_duty)
    );
`else
    wire [0:0] fan_en_b_bd;
    assign fan_en_b = fan_en_b_bd[0];
`endif

`ifdef USE_DP
    wire        vid_clk, vid_rst;           // PS video clock (74.25 MHz) and its reset
    wire [31:0] dp_ctrl;
    wire [35:0] vid_pixel;
    wire        vid_hsync, vid_vsync, vid_de;
    wire [15:0] vid_frames;
    (* ASYNC_REG = "TRUE" *) reg [15:0] frames_m, frames_s;   // to pl_clk (status only)

    dp_tpg u_tpg (
        .clk       (vid_clk),
        .rst       (vid_rst),
        .ctrl      (dp_ctrl),
        .pixel     (vid_pixel),
        .hsync     (vid_hsync),
        .vsync     (vid_vsync),
        .de        (vid_de),
        .frame_cnt (vid_frames)
    );

    always @(posedge pl_clk) begin
        frames_m <= vid_frames;
        frames_s <= frames_m;
    end
`endif

    system_wrapper u_system (
`ifdef USE_PMOD
        .pmod_tri_io (pmod),
`endif
`ifdef USE_FAN_RTL
        .fan_ctrl_o  (fan_ctrl),
        .fan_duty_i  (fan_duty),
`else
        .fan_en_b    (fan_en_b_bd),
`endif
`ifdef USE_IIC
        .iic_scl_io  (iic_scl),
        .iic_sda_io  (iic_sda),
        .cam_ctrl_o  (cam_ctrl),
`endif
`ifdef USE_CAM
        .mipi_cam_clk_p  (mipi_cam_clk_p),
        .mipi_cam_clk_n  (mipi_cam_clk_n),
        .mipi_cam_data_p (mipi_cam_data_p),
        .mipi_cam_data_n (mipi_cam_data_n),
`endif
`ifdef USE_DP
        .dp_ctrl_o   (dp_ctrl),
        .dp_frames_i (frames_s),
        .vid_clk     (vid_clk),
        .vid_rst     (vid_rst),
        .vid_pixel   (vid_pixel),
        .vid_hsync   (vid_hsync),
        .vid_vsync   (vid_vsync),
        .vid_de      (vid_de),
`endif
        .pl_clk      (pl_clk),
        .pl_rst      (pl_rst)
    );

endmodule

`default_nettype wire
