// Null BFM stub for Verilator — firmware loaded via XPM model per-bank hex files
module lcpu_bfm #(
    parameter read_time_out = 2000, parameter delay_time = 1000,
    parameter string script_file = "")
(
    input clk, input reset_l, input OP_DONE, input [31:0] RD_DATA,
    output [31:0] ADDRESS, output [31:0] WR_DATA, output RH_WL, output EXEC
);
    assign ADDRESS = 0; assign WR_DATA = 0; assign RH_WL = 1; assign EXEC = 0;
endmodule
