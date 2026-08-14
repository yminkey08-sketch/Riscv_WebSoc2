
// Comprehensive altsyncram stub for Verilator — all possible ports/params
module altsyncram #(
    parameter operation_mode = "BIDIR_DUAL_PORT",
    parameter width_a = 8, parameter widthad_a = 6, parameter numwords_a = 64,
    parameter width_b = 8, parameter widthad_b = 6, parameter numwords_b = 64,
    parameter outdata_reg_a = "UNREGISTERED", parameter outdata_reg_b = "UNREGISTERED",
    parameter power_up_high = "OFF", parameter intended_device_family = "Cyclone V",
    parameter width_byteena_a = 1, parameter width_byteena_b = 1,
    parameter read_during_write_mode_mixed_ports = "DONT_CARE",
    parameter ram_block_type = "AUTO", parameter lpm_type = "altsyncram",
    parameter maximum_depth = 0, parameter byte_size = 8,
    parameter clock_enable_input_a = "BYPASS", parameter clock_enable_input_b = "BYPASS",
    parameter clock_enable_output_a = "BYPASS", parameter clock_enable_output_b = "BYPASS",
    parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    parameter read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ"
) (
    input  [width_a-1:0] data_a, input  [widthad_a-1:0] address_a, input  wren_a, output [width_a-1:0] q_a,
    input  clock0, input  clocken0, input  rden_a, input  aclr0,
    input  [width_b-1:0] data_b, input  [widthad_b-1:0] address_b, input  wren_b, output [width_b-1:0] q_b,
    input  clock1, input  clocken1, input  rden_b, input  aclr1,
    input  [width_byteena_a-1:0] byteena_a, input  [width_byteena_b-1:0] byteena_b,
    input  addressstall_a, input  addressstall_b,
    output eccstatus
);
    reg [width_a-1:0] mem [0:numwords_a-1];
    reg [width_a-1:0] q_a_reg;
    reg [width_b-1:0] q_b_reg;
    integer _i_;
    initial for (_i_=0; _i_<numwords_a; _i_=_i_+1) mem[_i_]=0;
    assign q_a = q_a_reg;
    assign q_b = q_b_reg;
    assign eccstatus = 0;
    always @(posedge clock0) begin
        if (wren_a && !addressstall_a) mem[address_a] <= data_a;
        q_a_reg <= mem[address_a];
    end
    always @(posedge clock1) begin
        if (wren_b && !addressstall_b) mem[address_b] <= data_b;
        q_b_reg <= mem[address_b];
    end
endmodule
