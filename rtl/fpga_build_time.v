//-----------------------------------------------------------------
// fpga_build_time.v — FPGA 编译时间标记 (仿真用)
// 实际 FPGA 构建时由 build_fpga.sh 覆盖
//-----------------------------------------------------------------

module fpga_build_time (
    output wire [31:0] build_date,
    output wire [31:0] build_time
);
    assign build_date = 32'h20260727;
    assign build_time = 32'h00000001;
endmodule
