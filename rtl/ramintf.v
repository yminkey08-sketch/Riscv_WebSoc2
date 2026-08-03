module ramintf #(
    parameter DataBits = 32,
    parameter AddrBits = 16
) (
    input [DataBits-1:0] Ram_RdData,
    output reg Ram_RlWh,
    output reg [(DataBits/8)-1:0] Ram_ByteEn,
    output reg [AddrBits-1:0] Ram_Addr,
    output reg [DataBits-1:0] Ram_WrData,

    input clk,
    input rst_n,
    input req,
    input rhwl,
    input [(DataBits/8)-1:0] byte_en,
    input [DataBits-1:0] wdata,
    input [AddrBits-1:0] address,
    output reg [DataBits-1:0] rdata,
    output reg ack
);
  parameter ram_latency_cycles = 3;  /*consider RAM input&output registers*/
  localparam ByteEnBits = DataBits / 8;
  reg [ram_latency_cycles-1:0] req_d;
  reg [ram_latency_cycles-1:0] rhwl_d;

  always @(negedge rst_n or posedge clk)
    if (rst_n == 1'b0) begin
      req_d <= {ram_latency_cycles{1'b0}};
      rhwl_d <= {ram_latency_cycles{1'b0}};
      ack <= 1'b0;
      rdata <= {DataBits{1'b0}};
    end else begin
      req_d <= {req_d[ram_latency_cycles-2:0], req};
      rhwl_d <= {rhwl_d[ram_latency_cycles-2:0], rhwl};
      ack <= req_d[ram_latency_cycles-1];
      if (req_d[ram_latency_cycles-1] == 1'b1 && rhwl_d[ram_latency_cycles-1] == 1'b1) begin
        rdata[DataBits-1:0] <= Ram_RdData;
      end
    end

  always @(negedge rst_n or posedge clk)
    if (rst_n == 1'b0) begin
      Ram_Addr   <= {AddrBits{1'b0}};
      Ram_WrData <= {DataBits{1'b0}};
      Ram_RlWh   <= 1'b0;
      Ram_ByteEn <= {ByteEnBits{1'b1}};
    end else begin
      Ram_RlWh   <= 1'b0;
      Ram_ByteEn <= {ByteEnBits{1'b1}};
      if (req) Ram_RlWh <= !(rhwl);
      if (req) Ram_WrData <= wdata[DataBits-1:0];
      if (req) Ram_Addr <= address[AddrBits-1:0];
      if (req && !rhwl) Ram_ByteEn <= byte_en;
    end
endmodule
