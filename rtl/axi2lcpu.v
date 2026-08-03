module axi2lcpu #(
    parameter data_width = 32,
    parameter addr_width = 32
) (
    input resetl,
    input clk,
    input [addr_width-1:0] m_axi_awaddr,
    input m_axi_awvalid,
    output reg m_axi_awready,
    input [data_width-1:0] m_axi_wdata,
    //input [(data_width/8)-1:0] m_axi_wstrb,
    input m_axi_wvalid,
    output reg m_axi_wready,
    output reg [1:0] m_axi_bresp,
    output reg m_axi_bvalid,
    input m_axi_bready,
    input [addr_width-1:0] m_axi_araddr,
    input m_axi_arvalid,
    output reg m_axi_arready,
    output reg [data_width-1:0] m_axi_rdata,
    output reg [1:0] m_axi_rresp,
    output reg m_axi_rvalid,
    input m_axi_rready,

    output reg lcpu_rh_wl,
    output reg lcpu_req,
    input lcpu_ack,
    output reg [addr_width-1:0] lcpu_address,
    output reg [data_width-1:0] lcpu_wdata,
    input [data_width-1:0] lcpu_rdata
);


  // State encoding using Verilog's `localparam` for readability
  localparam idle = 3'd0,
			wait_rd_op_done = 3'd1,
			wait_axi_rready = 3'd2,
			wait_wr_op_done = 3'd3,
			wait_axi_bready = 3'd4,
			wait_one_clock = 3'd5;

  reg [2:0] state;

  always @(posedge clk or negedge resetl) begin
    if (~resetl) begin
      m_axi_awready <= 1'b0;
      m_axi_wready  <= 1'b0;
      lcpu_req      <= 1'b0;
      m_axi_bvalid  <= 1'b0;
      m_axi_arready <= 1'b0;
      m_axi_rvalid  <= 1'b0;
      m_axi_rdata   <= {data_width{1'b0}};
      lcpu_rh_wl    <= 1'b0;
      lcpu_address  <= {addr_width{1'b0}};
      lcpu_wdata    <= {data_width{1'b0}};
      m_axi_bresp   <= 2'b00;
      m_axi_rresp   <= 2'b00;
      state         <= idle;
    end else begin
      m_axi_awready <= 1'b0;
      m_axi_wready <= 1'b0;
      lcpu_req <= 1'b0;
      m_axi_bvalid <= 1'b0;
      m_axi_arready <= 1'b0;
      m_axi_rvalid <= 1'b0;

      case (state)
        idle: begin
          if (m_axi_awvalid && m_axi_wvalid) begin
            m_axi_awready <= 1'b1;
            m_axi_wready  <= 1'b1;
            lcpu_rh_wl    <= 1'b0;
            lcpu_req      <= 1'b1;
            lcpu_address  <= m_axi_awaddr;
            lcpu_wdata    <= m_axi_wdata;
            state         <= wait_wr_op_done;
          end else if (m_axi_arvalid) begin
            m_axi_arready <= 1'b1;
            lcpu_rh_wl    <= 1'b1;
            lcpu_req      <= 1'b1;
            lcpu_address  <= m_axi_araddr;
            state         <= wait_rd_op_done;
          end
        end

        wait_rd_op_done: begin
          if (lcpu_ack) begin
            m_axi_rvalid <= 1'b1;
            m_axi_rdata  <= lcpu_rdata;
            state        <= wait_axi_rready;
          end
        end

        wait_axi_rready: begin
          m_axi_rvalid <= 1'b1;
          if (m_axi_rready) begin
            m_axi_rvalid <= 1'b0;
            state        <= wait_one_clock;
          end
        end

        wait_wr_op_done: begin
          if (lcpu_ack) begin
            m_axi_bvalid <= 1'b1;
            state        <= wait_axi_bready;
          end
        end

        wait_axi_bready: begin
          m_axi_bvalid <= 1'b1;
          if (m_axi_bready) begin
            m_axi_bvalid <= 1'b0;
            state        <= wait_one_clock;
          end
        end

        wait_one_clock: begin
          state <= idle;
        end

        default: state <= idle;
      endcase
    end
  end
endmodule
