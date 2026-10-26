`default_nettype none
// -----------------------------------------------------------------------------
// reset_sync : asynchronous assert, synchronous release.
//   `rst` goes high as soon as `arst_n` is low and stays high for STAGES
//   clocks after it returns high.
// -----------------------------------------------------------------------------
module reset_sync #(
    parameter integer STAGES = 4
) (
    input  wire clk,
    input  wire arst_n,
    output wire rst
);
    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_q = {STAGES{1'b1}};

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) sync_q <= {STAGES{1'b1}};
        else         sync_q <= {sync_q[STAGES-2:0], 1'b0};
    end

    assign rst = sync_q[STAGES-1];
endmodule

`default_nettype wire
