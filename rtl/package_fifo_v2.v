//****************************************Copyright 2026[c]************************//
// File name:        package_fifo_v2.v
// Author:           huaming.huang@link-real.com.cn
// Date:             2026-05-28
// Version Number:   1.0
// Abstract:         包FIFO v2 — 支持块模式和非块变长包存储模式
//                   统一CDC架构(dual_clock_fifo+pulse_clock_region_pass)
//                   非块模式无最小包长限制，环形缓冲区动态分配
//
// Modification history:[time, version, author, abstract]
//
// *********************************end************************************** //

module package_fifo_v2 #(
    parameter dual_clock = 1,  // 1: 双时钟, 0: 单时钟
    parameter addr_width = 8,  // 块内地址位宽(块模式) / 总地址位宽(非块模式)
    parameter block_addr_width = 4, //按最大包长，可存储包的个数，2^4 = 16； 块地址位宽(仅块模式有效, 2^block_addr_width个块)
    parameter data_width = 32,  // 数据位宽
    parameter para_width = 16,  // 附带参数位宽
    parameter vendor = "",  //"intel";	"xilinx";
    parameter para_ram_type = "registers",  // 参数FIFO RAM类型: "M9K"或"registers"
    parameter data_ram_type = "M9K",  // 数据RAM类型: "M9K"或"registers"
    parameter block_ram_size = 32,  // 每块Block RAM数据位大小（Kbit，不含校验）
    parameter max_pkt_length = 1518,  // 最大包长(words, 仅非块模式有效)
    parameter block_mode = "true"  // "true": 块模式, "false": 非块变长模式
) (
    input reset_l,

    // 写侧
    input                   wclk,
    input                   wclk_en,
    output                  full,
    input                   wen,
    input  [addr_width-1:0] waddr,
    input  [data_width-1:0] wdata,
    input                   wpkt_push,
    input  [  addr_width:0] wpkt_len,
    input  [para_width-1:0] wpkt_para,

    // 读侧
    input                   rclk,
    input                   rclk_en,
    output                  empty,
    input                   rpkt_pop,
    output [  addr_width:0] rpkt_len,
    output [para_width-1:0] rpkt_para,
    input                   ren,
    input  [addr_width-1:0] raddr,
    output [data_width-1:0] rdata,
    output                  reop_pre,

    // 错误标志
    output reg overflow,
    output reg underflow
);

  // ============================================================
  // 块模式 (block_mode == "true")
  // ============================================================
  generate
    if (block_mode == "true") begin : blk_mode

      localparam PARA_FIFO_WIDTH = block_addr_width + para_width + addr_width + 1;
      localparam MAX_BLOCKS = 2 ** block_addr_width;
      localparam BLK_CNT_WIDTH = block_addr_width + 1;

      reg  [           block_addr_width-1:0] block_wptr;
      wire [            PARA_FIFO_WIDTH-1:0] wpkt_para_data;
      wire [            PARA_FIFO_WIDTH-1:0] rpkt_para_data;
      reg  [            PARA_FIFO_WIDTH-1:0] rpkt_para_data_r;
      reg  [           block_addr_width-1:0] block_raddr_reg;
      wire [block_addr_width+addr_width-1:0] wpkt_data_addr;
      wire [block_addr_width+addr_width-1:0] rpkt_data_addr;
      reg                                    rpkt_pop_d0;
      reg  [              BLK_CNT_WIDTH-1:0] block_cnt;
      wire                                   full_i;
      wire                                   empty_i;
      wire                                   rpkt_pop_wclk;

      assign full  = full_i;
      assign empty = empty_i;

      // 写指针管理
      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) block_wptr <= {block_addr_width{1'b0}};
        else if (wclk_en && wpkt_push && !full_i) block_wptr <= block_wptr + 1'b1;
      end

      // 块使用计数 (wclk域) — wpkt_push增, rpkt_pop_wclk减
      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) block_cnt <= {BLK_CNT_WIDTH{1'b0}};
        else if (wclk_en) begin
          if (wpkt_push && !full_i && !rpkt_pop_wclk) block_cnt <= block_cnt + 1'b1;
          else if (!wpkt_push && rpkt_pop_wclk && block_cnt > 0) block_cnt <= block_cnt - 1'b1;
        end
      end

      assign full_i = (block_cnt >= MAX_BLOCKS);

      // 打包参数: {block_wptr, wpkt_para, wpkt_len}
      assign wpkt_para_data = {block_wptr, wpkt_para, wpkt_len};

      // 解包参数
      always @(negedge reset_l or posedge rclk) begin
        if (reset_l == 1'b0) begin
          rpkt_pop_d0      <= 1'b0;
          rpkt_para_data_r <= 0;
          block_raddr_reg  <= {block_addr_width{1'b0}};
        end else if (rclk_en) begin
          rpkt_pop_d0 <= rpkt_pop;
          if (rpkt_pop_d0) begin
            rpkt_para_data_r <= rpkt_para_data;
            block_raddr_reg  <= rpkt_para_data[PARA_FIFO_WIDTH-1:para_width+addr_width+1];
          end
        end
      end

      assign rpkt_len  = rpkt_para_data_r[addr_width:0];
      assign rpkt_para = rpkt_para_data_r[para_width+addr_width:addr_width+1];

      // 参数FIFO + CDC
      // dual_clock: dual_clock_fifo(双时钟异步) + pulse_clock_region_pass
      // single_clk: single_clock_fifo(单时钟同步, 满容量2^n, 无读延迟)

      if (dual_clock == 1) begin : dual_clk_para
        pulse_clock_region_pass u_pop_sync (
            .reset_l(reset_l),
            .clk_a  (rclk),
            .pulse_a(rpkt_pop),
            .clk_b  (wclk),
            .pulse_b(rpkt_pop_wclk)
        );

        dual_clock_fifo #(
            .addr_width(block_addr_width),
            .data_width(PARA_FIFO_WIDTH),
            .ram_type  (para_ram_type)
        ) u_para_fifo (
            .reset_l   (reset_l),
            .wclk      (wclk),
            .write_en  (wpkt_push && !full_i),
            .write_data(wpkt_para_data),
            .full      (),
            .rclk      (rclk),
            .read_en   (rpkt_pop),
            .read_data (rpkt_para_data),
            .empty     (empty_i)
        );
      end else begin : single_clk_para
        assign rpkt_pop_wclk = rpkt_pop;

        single_clock_fifo #(
            .addr_width(block_addr_width),
            .data_width(PARA_FIFO_WIDTH),
            .ram_type  (para_ram_type)
        ) u_para_fifo (
            .clk       (wclk),
            .reset_l   (reset_l),
            .write_en  (wpkt_push && wclk_en && !full_i),
            .write_data(wpkt_para_data),
            .full      (),
            .read_en   (rpkt_pop && wclk_en),
            .read_data (rpkt_para_data),
            .empty     (empty_i)
        );
      end

      // 数据RAM — 写端口 pipeline 寄存器
      reg [block_addr_width+addr_width-1:0] ram_addr_a_r;
      reg                                   ram_wren_a_r;
      reg [                 data_width-1:0] ram_data_a_r;

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) begin
          ram_addr_a_r <= {(block_addr_width + addr_width) {1'b0}};
          ram_wren_a_r <= 1'b0;
          ram_data_a_r <= {data_width{1'b0}};
        end else if (wclk_en) begin
          ram_addr_a_r <= {block_wptr, waddr};
          ram_wren_a_r <= wen && !full;
          ram_data_a_r <= wdata;
        end
      end

      assign rpkt_data_addr = {block_raddr_reg, raddr};

      if (dual_clock == 1) begin : data_ram_dual
        dual_clock_simple_dual_port_ram #(
            .data_width    (data_width),
            .addr_width    (block_addr_width + addr_width),
            .depth         (2 ** (block_addr_width + addr_width)),
            .block_ram_size(block_ram_size),
            .ram_type      (data_ram_type),
            .vendor        (vendor)
        ) u_data_ram (
            .clock_a  (wclk),
            .clock_b  (rclk),
            .wren_a   (ram_wren_a_r),
            .data_a   (ram_data_a_r),
            .address_a(ram_addr_a_r),
            .address_b(rpkt_data_addr),
            .q_b      (rdata)
        );
      end else begin : data_ram_single
        single_clock_simple_dual_port_ram #(
            .data_width    (data_width),
            .depth         (2 ** (block_addr_width + addr_width)),
            .addr_width    (block_addr_width + addr_width),
            .block_ram_size(block_ram_size),
            .ram_type      (data_ram_type),
            .vendor        (vendor)
        ) u_data_ram (
            .clk      (wclk),
            .wren_a   (ram_wren_a_r),
            .data_a   (ram_data_a_r),
            .address_a(ram_addr_a_r),
            .address_b(rpkt_data_addr),
            .q_b      (rdata)
        );
      end

      assign reop_pre = 1'b0;

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) begin
          overflow <= 1'b0;
        end else if (wclk_en) begin
          if (wpkt_push && full) overflow <= 1'b1;
          else overflow <= 1'b0;
          if (rpkt_pop && empty) underflow <= 1'b1;
          else underflow <= 1'b0;
        end
      end

    end else begin : none_blk_mode
      // ============================================================
      // 非块变长模式 (block_mode == "false")
      // ============================================================

      localparam NB_PARA_FIFO_WIDTH = addr_width + para_width + addr_width + 1;

      reg [addr_width-1:0] nb_wptr;
      reg [addr_width-1:0] nb_rptr_wclk_s1;
      reg [addr_width-1:0] nb_rptr_wclk_s2;
      reg [addr_width-1:0] nb_rptr;
      wire [NB_PARA_FIFO_WIDTH-1:0] wpkt_para_data;
      wire [NB_PARA_FIFO_WIDTH-1:0] rpkt_para_data;
      reg [NB_PARA_FIFO_WIDTH-1:0] rpkt_para_data_r;
      reg [addr_width-1:0] nb_rptr_reg;
      reg rpkt_pop_d0;
      wire full_i;
      reg full_reg;
      wire empty_i;
      wire rpkt_pop_wclk;

      assign full  = full_reg;
      assign empty = empty_i;

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) nb_wptr <= {addr_width{1'b0}};
        else if (wclk_en && wpkt_push && !full_reg) nb_wptr <= nb_wptr + wpkt_len;
      end

      // para FIFO 写端口 pipeline（切断 nb_wptr→FIFO mem_array 路径）
      reg [NB_PARA_FIFO_WIDTH-1:0] para_wdata_r;
      reg                          para_wen_r;

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) begin
          para_wdata_r <= {NB_PARA_FIFO_WIDTH{1'b0}};
          para_wen_r   <= 1'b0;
        end else if (wclk_en) begin
          para_wdata_r <= {nb_wptr, wpkt_para, wpkt_len};
          para_wen_r   <= wpkt_push && !full_reg;
        end
      end

      always @(negedge reset_l or posedge rclk) begin
        if (reset_l == 1'b0) begin
          nb_rptr <= {addr_width{1'b0}};
        end else if (rclk_en && rpkt_pop_d0) begin
          nb_rptr <= nb_rptr_reg;
        end
      end

      if (dual_clock == 1) begin : nb_dual_clk_cdc
        pulse_clock_region_pass u_rptr_sync (
            .reset_l(reset_l),
            .clk_a  (rclk),
            .pulse_a(rpkt_pop),
            .clk_b  (wclk),
            .pulse_b(rpkt_pop_wclk)
        );

        dual_clock_fifo #(
            .addr_width(block_addr_width),
            .data_width(NB_PARA_FIFO_WIDTH),
            .ram_type  (para_ram_type)
        ) u_para_fifo (
            .reset_l   (reset_l),
            .wclk      (wclk),
            .write_en  (para_wen_r),
            .write_data(para_wdata_r),
            .full      (),
            .rclk      (rclk),
            .read_en   (rpkt_pop),
            .read_data (rpkt_para_data),
            .empty     (empty_i)
        );

      end else begin : nb_single_clk
        assign rpkt_pop_wclk = rpkt_pop;

        single_clock_fifo #(
            .addr_width(block_addr_width),
            .data_width(NB_PARA_FIFO_WIDTH),
            .ram_type  (para_ram_type)
        ) u_para_fifo (
            .clk       (wclk),
            .reset_l   (reset_l),
            .write_en  (para_wen_r && wclk_en),
            .write_data(para_wdata_r),
            .full      (),
            .read_en   (rpkt_pop && wclk_en),
            .read_data (rpkt_para_data),
            .empty     (empty_i)
        );
      end

      always @(negedge reset_l or posedge rclk) begin
        if (reset_l == 1'b0) begin
          rpkt_pop_d0      <= 1'b0;
          rpkt_para_data_r <= 0;
          nb_rptr_reg      <= {addr_width{1'b0}};
        end else if (rclk_en) begin
          rpkt_pop_d0 <= rpkt_pop;
          if (rpkt_pop_d0) begin
            rpkt_para_data_r <= rpkt_para_data;
            nb_rptr_reg <= rpkt_para_data[NB_PARA_FIFO_WIDTH-1:para_width+addr_width+1] + rpkt_para_data[addr_width:0];
          end
        end
      end

      assign rpkt_len  = rpkt_para_data_r[addr_width:0];
      assign rpkt_para = rpkt_para_data_r[para_width+addr_width:addr_width+1];

      wire [addr_width:0] avail_space;
      wire [addr_width:0] wptr_ext;
      wire [addr_width:0] rptr_ext;
      wire [addr_width:0] used_words;

      assign wptr_ext = {1'b0, nb_wptr};
      assign rptr_ext = {1'b0, nb_rptr_wclk_s2};

      assign used_words = (wptr_ext >= rptr_ext) ? (wptr_ext - rptr_ext) :
								((1 << (addr_width+1)) - rptr_ext + wptr_ext);
      assign avail_space = (1 << addr_width) - used_words;
      assign full_i = (avail_space < max_pkt_length);

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) full_reg <= 1'b0;
        else full_reg <= full_i;
      end

      wire [NB_PARA_FIFO_WIDTH-1:0] rpkt_para_data_wclk;

      if (dual_clock == 1) begin : nb_rptr_cdc
        dual_clock_fifo #(
            .addr_width(block_addr_width),
            .data_width(NB_PARA_FIFO_WIDTH),
            .ram_type  (para_ram_type)
        ) u_para_fifo_wclk (
            .reset_l   (reset_l),
            .wclk      (wclk),
            .write_en  (para_wen_r),
            .write_data(para_wdata_r),
            .full      (),
            .rclk      (wclk),
            .read_en   (rpkt_pop_wclk),
            .read_data (rpkt_para_data_wclk),
            .empty     ()
        );

        reg rpkt_pop_wclk_d0;
        reg [addr_width-1:0] nb_rptr_wclk_latch;
        always @(negedge reset_l or posedge wclk) begin
          if (reset_l == 1'b0) begin
            rpkt_pop_wclk_d0   <= 1'b0;
            nb_rptr_wclk_latch <= {addr_width{1'b0}};
            nb_rptr_wclk_s1    <= {addr_width{1'b0}};
            nb_rptr_wclk_s2    <= {addr_width{1'b0}};
          end else begin
            rpkt_pop_wclk_d0 <= rpkt_pop_wclk;
            nb_rptr_wclk_s1  <= nb_rptr_wclk_latch;
            nb_rptr_wclk_s2  <= nb_rptr_wclk_s1;
            if (rpkt_pop_wclk_d0)
              nb_rptr_wclk_latch <= rpkt_para_data_wclk[NB_PARA_FIFO_WIDTH-1:para_width+addr_width+1] + rpkt_para_data_wclk[addr_width:0];
          end
        end
      end else begin : nb_no_rptr_cdc
        always_comb begin
          nb_rptr_wclk_s1 = nb_rptr;
          nb_rptr_wclk_s2 = nb_rptr;
        end
      end

      wire [addr_width-1:0] wpkt_data_addr;
      wire [addr_width-1:0] rpkt_data_addr;
      reg  [addr_width-1:0] nb_rptr_for_data;

      always @(negedge reset_l or posedge rclk) begin
        if (reset_l == 1'b0) nb_rptr_for_data <= {addr_width{1'b0}};
        else if (rclk_en && rpkt_pop_d0)
          nb_rptr_for_data <= rpkt_para_data[NB_PARA_FIFO_WIDTH-1:para_width+addr_width+1];
      end

      // 数据RAM — 写端口 pipeline 寄存器（切断 nb_wptr→+→RAM 组合路径）
      reg [addr_width-1:0] ram_addr_a_r;
      reg                  ram_wren_a_r;
      reg [data_width-1:0] ram_data_a_r;

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) begin
          ram_addr_a_r <= {addr_width{1'b0}};
          ram_wren_a_r <= 1'b0;
          ram_data_a_r <= {data_width{1'b0}};
        end else if (wclk_en) begin
          ram_addr_a_r <= nb_wptr + waddr;
          ram_wren_a_r <= wen && !full_reg;
          ram_data_a_r <= wdata;
        end
      end

      assign rpkt_data_addr = nb_rptr_for_data + raddr;

      if (dual_clock == 1) begin : data_ram_dual
        dual_clock_simple_dual_port_ram #(
            .data_width    (data_width),
            .addr_width    (addr_width),
            .depth         (2 ** addr_width),
            .block_ram_size(block_ram_size),
            .ram_type      (data_ram_type),
            .vendor        (vendor)
        ) u_data_ram (
            .clock_a  (wclk),
            .clock_b  (rclk),
            .wren_a   (ram_wren_a_r),
            .data_a   (ram_data_a_r),
            .address_a(ram_addr_a_r),
            .address_b(rpkt_data_addr),
            .q_b      (rdata)
        );
      end else begin : data_ram_single
        single_clock_simple_dual_port_ram #(
            .data_width    (data_width),
            .depth         (2 ** addr_width),
            .addr_width    (addr_width),
            .block_ram_size(block_ram_size),
            .ram_type      (data_ram_type),
            .vendor        (vendor)
        ) u_data_ram (
            .clk      (wclk),
            .wren_a   (ram_wren_a_r),
            .data_a   (ram_data_a_r),
            .address_a(ram_addr_a_r),
            .address_b(rpkt_data_addr),
            .q_b      (rdata)
        );
      end

      assign reop_pre = 1'b0;

      always @(negedge reset_l or posedge wclk) begin
        if (reset_l == 1'b0) begin
          overflow <= 1'b0;
        end else if (wclk_en) begin
          if (wpkt_push && full_reg) overflow <= 1'b1;
          else overflow <= 1'b0;
        end
      end

      always @(negedge reset_l or posedge rclk) begin
        if (reset_l == 1'b0) underflow <= 1'b0;
        else if (rclk_en) begin
          if (rpkt_pop && empty_i) underflow <= 1'b1;
          else underflow <= 1'b0;
        end
      end

    end
  endgenerate
endmodule


// synthesis translate_off

module tb_package_fifo_v2 ();

  // ============================================================
  // SC+BLK Tasks (clk 域)
  // ============================================================
  task blk_write_pkt;
    input [ADDR_WIDTH:0] len;
    input [PARA_WIDTH-1:0] para;
    integer jj;
    begin
      for (jj = 0; jj < len; jj = jj + 1) begin
        blk_wen   <= 1'b1;
        blk_waddr <= jj;
        blk_wdata <= jj;
        @(posedge clk);
      end
      blk_wen       <= 1'b0;
      blk_wpkt_push <= 1'b1;
      blk_wpkt_len  <= len;
      blk_wpkt_para <= para;
      @(posedge clk);
      blk_wpkt_push <= 1'b0;
    end
  endtask

  task blk_read_pkt;
    input [ADDR_WIDTH:0] exp_len;
    input [PARA_WIDTH-1:0] exp_para;
    integer jj;
    begin
      while (blk_empty) @(posedge clk);
      @(posedge clk);
      blk_rpkt_pop <= 1'b1;
      @(posedge clk);
      blk_rpkt_pop <= 1'b0;
      repeat (3) @(posedge clk);

      if (blk_rpkt_len != exp_len) begin
        $display("  [SC+BLK] FAIL: rpkt_len=%d expected=%d", blk_rpkt_len, exp_len);
        err_blk_sc = err_blk_sc + 1;
      end
      if (blk_rpkt_para != exp_para) begin
        $display("  [SC+BLK] FAIL: rpkt_para=%h expected=%h", blk_rpkt_para, exp_para);
        err_blk_sc = err_blk_sc + 1;
      end

      for (jj = 0; jj < blk_rpkt_len; jj = jj + 1) begin
        blk_ren   <= 1'b1;
        blk_raddr <= jj;
        @(posedge clk);
        @(posedge clk);
        if (blk_rdata != jj) begin
          $display("  [SC+BLK] FAIL: rdata[%0d]=%h expected=%0d", jj, blk_rdata, jj);
          err_blk_sc = err_blk_sc + 1;
          if (err_blk_sc > 10) jj = blk_rpkt_len;
        end
      end
      blk_ren   <= 1'b0;
      blk_raddr <= 0;
    end
  endtask

  // ============================================================
  // SC+NB Tasks (clk 域)
  // ============================================================
  task nb_write_pkt;
    input [ADDR_WIDTH:0] len;
    input [PARA_WIDTH-1:0] para;
    integer jj;
    begin
      while (nb_full) @(posedge clk);
      for (jj = 0; jj < len; jj = jj + 1) begin
        nb_wen   <= 1'b1;
        nb_waddr <= jj;
        nb_wdata <= jj;
        @(posedge clk);
      end
      nb_wen       <= 1'b0;
      nb_wpkt_push <= 1'b1;
      nb_wpkt_len  <= len;
      nb_wpkt_para <= para;
      @(posedge clk);
      nb_wpkt_push <= 1'b0;
    end
  endtask

  task nb_read_pkt;
    input [ADDR_WIDTH:0] exp_len;
    input [PARA_WIDTH-1:0] exp_para;
    integer jj;
    begin
      while (nb_empty) @(posedge clk);
      @(posedge clk);
      nb_rpkt_pop <= 1'b1;
      @(posedge clk);
      nb_rpkt_pop <= 1'b0;
      repeat (3) @(posedge clk);

      if (nb_rpkt_len != exp_len) begin
        $display("  [SC+NB] FAIL: rpkt_len=%d expected=%d", nb_rpkt_len, exp_len);
        err_nb_sc = err_nb_sc + 1;
      end
      if (nb_rpkt_para != exp_para) begin
        $display("  [SC+NB] FAIL: rpkt_para=%h expected=%h", nb_rpkt_para, exp_para);
        err_nb_sc = err_nb_sc + 1;
      end

      for (jj = 0; jj < nb_rpkt_len; jj = jj + 1) begin
        nb_ren   <= 1'b1;
        nb_raddr <= jj;
        @(posedge clk);
        @(posedge clk);
        if (nb_rdata != jj) begin
          $display("  [SC+NB] FAIL: rdata[%0d]=%h expected=%0d", jj, nb_rdata, jj);
          err_nb_sc = err_nb_sc + 1;
          if (err_nb_sc > 10) jj = nb_rpkt_len;
        end
      end
      nb_ren   <= 1'b0;
      nb_raddr <= 0;
    end
  endtask

  // ============================================================
  // DC+BLK Tasks (写 wclk_dc 域, 读 rclk_dc 域)
  // ============================================================
  task blk_dc_write_pkt;
    input [ADDR_WIDTH:0] len;
    input [PARA_WIDTH-1:0] para;
    integer jj;
    begin
      for (jj = 0; jj < len; jj = jj + 1) begin
        blk_dc_wen   <= 1'b1;
        blk_dc_waddr <= jj;
        blk_dc_wdata <= jj;
        @(posedge wclk_dc);
      end
      blk_dc_wen       <= 1'b0;
      blk_dc_wpkt_push <= 1'b1;
      blk_dc_wpkt_len  <= len;
      blk_dc_wpkt_para <= para;
      @(posedge wclk_dc);
      blk_dc_wpkt_push <= 1'b0;
    end
  endtask

  task blk_dc_read_pkt;
    input [ADDR_WIDTH:0] exp_len;
    input [PARA_WIDTH-1:0] exp_para;
    integer jj;
    begin
      while (blk_dc_empty) @(posedge rclk_dc);
      @(posedge rclk_dc);
      blk_dc_rpkt_pop <= 1'b1;
      @(posedge rclk_dc);
      blk_dc_rpkt_pop <= 1'b0;
      // CDC + 内部流水延迟
      repeat (8) @(posedge rclk_dc);

      if (blk_dc_rpkt_len != exp_len) begin
        $display("  [DC+BLK] FAIL: rpkt_len=%d expected=%d", blk_dc_rpkt_len, exp_len);
        err_blk_dc = err_blk_dc + 1;
      end
      if (blk_dc_rpkt_para != exp_para) begin
        $display("  [DC+BLK] FAIL: rpkt_para=%h expected=%h", blk_dc_rpkt_para, exp_para);
        err_blk_dc = err_blk_dc + 1;
      end

      for (jj = 0; jj < blk_dc_rpkt_len; jj = jj + 1) begin
        blk_dc_ren   <= 1'b1;
        blk_dc_raddr <= jj;
        @(posedge rclk_dc);
        @(posedge rclk_dc);
        if (blk_dc_rdata != jj) begin
          $display("  [DC+BLK] FAIL: rdata[%0d]=%h expected=%0d", jj, blk_dc_rdata, jj);
          err_blk_dc = err_blk_dc + 1;
          if (err_blk_dc > 10) jj = blk_dc_rpkt_len;
        end
      end
      blk_dc_ren   <= 1'b0;
      blk_dc_raddr <= 0;
    end
  endtask

  // ============================================================
  // DC+NB Tasks (写 wclk_dc 域, 读 rclk_dc 域)
  // ============================================================
  task nb_dc_write_pkt;
    input [ADDR_WIDTH:0] len;
    input [PARA_WIDTH-1:0] para;
    integer jj;
    begin
      while (nb_dc_full) @(posedge wclk_dc);
      for (jj = 0; jj < len; jj = jj + 1) begin
        nb_dc_wen   <= 1'b1;
        nb_dc_waddr <= jj;
        nb_dc_wdata <= jj;
        @(posedge wclk_dc);
      end
      nb_dc_wen       <= 1'b0;
      nb_dc_wpkt_push <= 1'b1;
      nb_dc_wpkt_len  <= len;
      nb_dc_wpkt_para <= para;
      @(posedge wclk_dc);
      nb_dc_wpkt_push <= 1'b0;
    end
  endtask

  task nb_dc_read_pkt;
    input [ADDR_WIDTH:0] exp_len;
    input [PARA_WIDTH-1:0] exp_para;
    integer jj;
    begin
      while (nb_dc_empty) @(posedge rclk_dc);
      @(posedge rclk_dc);
      nb_dc_rpkt_pop <= 1'b1;
      @(posedge rclk_dc);
      nb_dc_rpkt_pop <= 1'b0;
      repeat (8) @(posedge rclk_dc);

      if (nb_dc_rpkt_len != exp_len) begin
        $display("  [DC+NB] FAIL: rpkt_len=%d expected=%d", nb_dc_rpkt_len, exp_len);
        err_nb_dc = err_nb_dc + 1;
      end
      if (nb_dc_rpkt_para != exp_para) begin
        $display("  [DC+NB] FAIL: rpkt_para=%h expected=%h", nb_dc_rpkt_para, exp_para);
        err_nb_dc = err_nb_dc + 1;
      end

      for (jj = 0; jj < nb_dc_rpkt_len; jj = jj + 1) begin
        nb_dc_ren   <= 1'b1;
        nb_dc_raddr <= jj;
        @(posedge rclk_dc);
        @(posedge rclk_dc);
        if (nb_dc_rdata != jj) begin
          $display("  [DC+NB] FAIL: rdata[%0d]=%h expected=%0d", jj, nb_dc_rdata, jj);
          err_nb_dc = err_nb_dc + 1;
          if (err_nb_dc > 10) jj = nb_dc_rpkt_len;
        end
      end
      nb_dc_ren   <= 1'b0;
      nb_dc_raddr <= 0;
    end
  endtask

  localparam ADDR_WIDTH = 8;
  localparam BLOCK_ADDR_WIDTH = 4;
  localparam DATA_WIDTH = 32;
  localparam PARA_WIDTH = 16;

  // ============================================================
  // 时钟 & 复位
  // ============================================================
  reg                   clk;  // 单时钟域
  reg                   wclk_dc;  // 双时钟写域
  reg                   rclk_dc;  // 双时钟读域 (与wclk不同频率，验证CDC)
  reg                   reset_l;
  reg  [           2:0] test_done_cnt;

  // ============================================================
  // DUT 1: 单时钟 + 块模式 (SC+BLK)
  // ============================================================
  wire                  blk_full;
  reg                   blk_wen;
  reg  [ADDR_WIDTH-1:0] blk_waddr;
  reg  [DATA_WIDTH-1:0] blk_wdata;
  reg                   blk_wpkt_push;
  reg  [  ADDR_WIDTH:0] blk_wpkt_len;
  reg  [PARA_WIDTH-1:0] blk_wpkt_para;
  wire                  blk_empty;
  reg                   blk_rpkt_pop;
  wire [  ADDR_WIDTH:0] blk_rpkt_len;
  wire [PARA_WIDTH-1:0] blk_rpkt_para;
  reg                   blk_ren;
  reg  [ADDR_WIDTH-1:0] blk_raddr;
  wire [DATA_WIDTH-1:0] blk_rdata;

  // ============================================================
  // DUT 2: 单时钟 + 非块模式 (SC+NB)
  // ============================================================
  wire                  nb_full;
  reg                   nb_wen;
  reg  [ADDR_WIDTH-1:0] nb_waddr;
  reg  [DATA_WIDTH-1:0] nb_wdata;
  reg                   nb_wpkt_push;
  reg  [  ADDR_WIDTH:0] nb_wpkt_len;
  reg  [PARA_WIDTH-1:0] nb_wpkt_para;
  wire                  nb_empty;
  reg                   nb_rpkt_pop;
  wire [  ADDR_WIDTH:0] nb_rpkt_len;
  wire [PARA_WIDTH-1:0] nb_rpkt_para;
  reg                   nb_ren;
  reg  [ADDR_WIDTH-1:0] nb_raddr;
  wire [DATA_WIDTH-1:0] nb_rdata;

  // ============================================================
  // DUT 3: 双时钟 + 块模式 (DC+BLK)
  // ============================================================
  wire                  blk_dc_full;
  reg                   blk_dc_wen;
  reg  [ADDR_WIDTH-1:0] blk_dc_waddr;
  reg  [DATA_WIDTH-1:0] blk_dc_wdata;
  reg                   blk_dc_wpkt_push;
  reg  [  ADDR_WIDTH:0] blk_dc_wpkt_len;
  reg  [PARA_WIDTH-1:0] blk_dc_wpkt_para;
  wire                  blk_dc_empty;
  reg                   blk_dc_rpkt_pop;
  wire [  ADDR_WIDTH:0] blk_dc_rpkt_len;
  wire [PARA_WIDTH-1:0] blk_dc_rpkt_para;
  reg                   blk_dc_ren;
  reg  [ADDR_WIDTH-1:0] blk_dc_raddr;
  wire [DATA_WIDTH-1:0] blk_dc_rdata;

  // ============================================================
  // DUT 4: 双时钟 + 非块模式 (DC+NB)
  // ============================================================
  wire                  nb_dc_full;
  reg                   nb_dc_wen;
  reg  [ADDR_WIDTH-1:0] nb_dc_waddr;
  reg  [DATA_WIDTH-1:0] nb_dc_wdata;
  reg                   nb_dc_wpkt_push;
  reg  [  ADDR_WIDTH:0] nb_dc_wpkt_len;
  reg  [PARA_WIDTH-1:0] nb_dc_wpkt_para;
  wire                  nb_dc_empty;
  reg                   nb_dc_rpkt_pop;
  wire [  ADDR_WIDTH:0] nb_dc_rpkt_len;
  wire [PARA_WIDTH-1:0] nb_dc_rpkt_para;
  reg                   nb_dc_ren;
  reg  [ADDR_WIDTH-1:0] nb_dc_raddr;
  wire [DATA_WIDTH-1:0] nb_dc_rdata;

  // ============================================================
  // 各组合独立错误计数器
  // ============================================================
  integer err_blk_sc, err_nb_sc, err_blk_dc, err_nb_dc;

  package_fifo_v2 #(
      .dual_clock      (0),
      .addr_width      (ADDR_WIDTH),
      .block_addr_width(BLOCK_ADDR_WIDTH),
      .data_width      (DATA_WIDTH),
      .para_width      (PARA_WIDTH),
      .data_ram_type   ("registers"),
      .block_mode      ("true")
  ) u_dut_blk_sc (
      .reset_l  (reset_l),
      .wclk     (clk),
      .wclk_en  (1'b1),
      .full     (blk_full),
      .wen      (blk_wen),
      .waddr    (blk_waddr),
      .wdata    (blk_wdata),
      .wpkt_push(blk_wpkt_push),
      .wpkt_len (blk_wpkt_len),
      .wpkt_para(blk_wpkt_para),
      .rclk     (clk),
      .rclk_en  (1'b1),
      .empty    (blk_empty),
      .rpkt_pop (blk_rpkt_pop),
      .rpkt_len (blk_rpkt_len),
      .rpkt_para(blk_rpkt_para),
      .ren      (blk_ren),
      .raddr    (blk_raddr),
      .rdata    (blk_rdata),
      .reop_pre (),
      .overflow (),
      .underflow()
  );

  package_fifo_v2 #(
      .dual_clock    (0),
      .addr_width    (ADDR_WIDTH),
      .data_width    (DATA_WIDTH),
      .para_width    (PARA_WIDTH),
      .data_ram_type ("registers"),
      .para_ram_type ("registers"),
      .max_pkt_length(60),
      .block_mode    ("false")
  ) u_dut_nb_sc (
      .reset_l  (reset_l),
      .wclk     (clk),
      .wclk_en  (1'b1),
      .full     (nb_full),
      .wen      (nb_wen),
      .waddr    (nb_waddr),
      .wdata    (nb_wdata),
      .wpkt_push(nb_wpkt_push),
      .wpkt_len (nb_wpkt_len),
      .wpkt_para(nb_wpkt_para),
      .rclk     (clk),
      .rclk_en  (1'b1),
      .empty    (nb_empty),
      .rpkt_pop (nb_rpkt_pop),
      .rpkt_len (nb_rpkt_len),
      .rpkt_para(nb_rpkt_para),
      .ren      (nb_ren),
      .raddr    (nb_raddr),
      .rdata    (nb_rdata),
      .reop_pre (),
      .overflow (),
      .underflow()
  );

  package_fifo_v2 #(
      .dual_clock      (1),
      .addr_width      (ADDR_WIDTH),
      .block_addr_width(BLOCK_ADDR_WIDTH),
      .data_width      (DATA_WIDTH),
      .para_width      (PARA_WIDTH),
      .data_ram_type   ("registers"),
      .block_mode      ("true")
  ) u_dut_blk_dc (
      .reset_l  (reset_l),
      .wclk     (wclk_dc),
      .wclk_en  (1'b1),
      .full     (blk_dc_full),
      .wen      (blk_dc_wen),
      .waddr    (blk_dc_waddr),
      .wdata    (blk_dc_wdata),
      .wpkt_push(blk_dc_wpkt_push),
      .wpkt_len (blk_dc_wpkt_len),
      .wpkt_para(blk_dc_wpkt_para),
      .rclk     (rclk_dc),
      .rclk_en  (1'b1),
      .empty    (blk_dc_empty),
      .rpkt_pop (blk_dc_rpkt_pop),
      .rpkt_len (blk_dc_rpkt_len),
      .rpkt_para(blk_dc_rpkt_para),
      .ren      (blk_dc_ren),
      .raddr    (blk_dc_raddr),
      .rdata    (blk_dc_rdata),
      .reop_pre (),
      .overflow (),
      .underflow()
  );

  package_fifo_v2 #(
      .dual_clock    (1),
      .addr_width    (ADDR_WIDTH),
      .data_width    (DATA_WIDTH),
      .para_width    (PARA_WIDTH),
      .data_ram_type ("registers"),
      .para_ram_type ("registers"),
      .max_pkt_length(60),
      .block_mode    ("false")
  ) u_dut_nb_dc (
      .reset_l  (reset_l),
      .wclk     (wclk_dc),
      .wclk_en  (1'b1),
      .full     (nb_dc_full),
      .wen      (nb_dc_wen),
      .waddr    (nb_dc_waddr),
      .wdata    (nb_dc_wdata),
      .wpkt_push(nb_dc_wpkt_push),
      .wpkt_len (nb_dc_wpkt_len),
      .wpkt_para(nb_dc_wpkt_para),
      .rclk     (rclk_dc),
      .rclk_en  (1'b1),
      .empty    (nb_dc_empty),
      .rpkt_pop (nb_dc_rpkt_pop),
      .rpkt_len (nb_dc_rpkt_len),
      .rpkt_para(nb_dc_rpkt_para),
      .ren      (nb_dc_ren),
      .raddr    (nb_dc_raddr),
      .rdata    (nb_dc_rdata),
      .reop_pre (),
      .overflow (),
      .underflow()
  );

  // ============================================================
  // 时钟生成
  // ============================================================
  always #10 clk = ~clk;  // 50MHz  单时钟域
  always #10 wclk_dc = ~wclk_dc;  // 50MHz  双时钟写域
  always #13 rclk_dc = ~rclk_dc;  // ~38MHz 双时钟读域 (与wclk异频，验证CDC)

  // ============================================================
  // 全局初始化
  // ============================================================
  initial begin
    clk              = 1'b0;
    wclk_dc          = 1'b0;
    rclk_dc          = 1'b0;
    reset_l          = 1'b0;

    // SC+BLK
    blk_wen          = 1'b0;
    blk_waddr        = 0;
    blk_wdata        = 0;
    blk_wpkt_push    = 1'b0;
    blk_wpkt_len     = 0;
    blk_wpkt_para    = 0;
    blk_rpkt_pop     = 1'b0;
    blk_ren          = 1'b0;
    blk_raddr        = 0;

    // SC+NB
    nb_wen           = 1'b0;
    nb_waddr         = 0;
    nb_wdata         = 0;
    nb_wpkt_push     = 1'b0;
    nb_wpkt_len      = 0;
    nb_wpkt_para     = 0;
    nb_rpkt_pop      = 1'b0;
    nb_ren           = 1'b0;
    nb_raddr         = 0;

    // DC+BLK
    blk_dc_wen       = 1'b0;
    blk_dc_waddr     = 0;
    blk_dc_wdata     = 0;
    blk_dc_wpkt_push = 1'b0;
    blk_dc_wpkt_len  = 0;
    blk_dc_wpkt_para = 0;
    blk_dc_rpkt_pop  = 1'b0;
    blk_dc_ren       = 1'b0;
    blk_dc_raddr     = 0;

    // DC+NB
    nb_dc_wen        = 1'b0;
    nb_dc_waddr      = 0;
    nb_dc_wdata      = 0;
    nb_dc_wpkt_push  = 1'b0;
    nb_dc_wpkt_len   = 0;
    nb_dc_wpkt_para  = 0;
    nb_dc_rpkt_pop   = 1'b0;
    nb_dc_ren        = 1'b0;
    nb_dc_raddr      = 0;

    err_blk_sc       = 0;
    err_nb_sc        = 0;
    err_blk_dc       = 0;
    err_nb_dc        = 0;
    test_done_cnt    = 0;

    #100 reset_l = 1'b1;
    repeat (5) @(posedge clk);
  end

  // ============================================================
  // Test 1: SC+BLK (单时钟 + 块模式)
  // ============================================================
  initial begin : test_sc_blk
    integer i;
    @(posedge reset_l);
    repeat (5) @(posedge clk);

    $display("============================================");
    $display("=== Test 1: SC+BLK (单时钟+块模式) ===");
    $display("============================================");

    // BLK-1: 串行写3读3
    $display("--- BLK-1: 写3读3 ---");
    blk_write_pkt(9'd8, 16'hA001);
    blk_write_pkt(9'd16, 16'hA002);
    blk_write_pkt(9'd4, 16'hA003);
    blk_read_pkt(9'd8, 16'hA001);
    blk_read_pkt(9'd16, 16'hA002);
    blk_read_pkt(9'd4, 16'hA003);
    $display("  SC+BLK BLK-1 errors=%0d", err_blk_sc);

    // BLK-2: 写满16个块
    $display("--- BLK-2: 写满16个块 ---");
    for (i = 0; i < 16; i = i + 1) blk_write_pkt(9'd10, i[PARA_WIDTH-1:0]);
    repeat (5) @(posedge clk);
    if (!blk_full) $display("  WARN: full not asserted, full=%b", blk_full);
    else $display("  full asserted OK");

    // BLK-3: 读出8个
    $display("--- BLK-3: 读出8个 ---");
    for (i = 0; i < 8; i = i + 1) blk_read_pkt(9'd10, i[PARA_WIDTH-1:0]);
    $display("  SC+BLK BLK-3 errors=%0d", err_blk_sc);

    // BLK-4: 读完剩余8个
    $display("--- BLK-4: 读完剩余8个 ---");
    for (i = 8; i < 16; i = i + 1) blk_read_pkt(9'd10, i[PARA_WIDTH-1:0]);
    $display("  SC+BLK BLK-4 errors=%0d", err_blk_sc);

    // BLK-5: 单word边界
    $display("--- BLK-5: 单word边界 ---");
    blk_write_pkt(9'd1, 16'hBEEF);
    blk_read_pkt(9'd1, 16'hBEEF);
    $display("  SC+BLK BLK-5 errors=%0d", err_blk_sc);

    $display("=== SC+BLK DONE: errors=%0d ===", err_blk_sc);
    test_done_cnt = test_done_cnt + 1;
  end

  // ============================================================
  // Test 2: SC+NB (单时钟 + 非块模式)
  // ============================================================
  initial begin : test_sc_nb
    integer i;
    @(posedge reset_l);
    repeat (5) @(posedge clk);

    $display("============================================");
    $display("=== Test 2: SC+NB (单时钟+非块模式) ===");
    $display("============================================");

    // NB-1: 串行写3读3
    $display("--- NB-1: 写3读3 ---");
    nb_write_pkt(9'd7, 16'hC001);
    nb_write_pkt(9'd20, 16'hC002);
    nb_write_pkt(9'd3, 16'hC003);
    nb_read_pkt(9'd7, 16'hC001);
    nb_read_pkt(9'd20, 16'hC002);
    nb_read_pkt(9'd3, 16'hC003);
    $display("  SC+NB NB-1 errors=%0d", err_nb_sc);

    // NB-2: 填充buffer
    $display("--- NB-2: 填充buffer (4包/170 words) ---");
    nb_write_pkt(9'd55, 16'hD001);
    nb_write_pkt(9'd55, 16'hD002);
    nb_write_pkt(9'd55, 16'hD003);
    nb_write_pkt(9'd5, 16'hD004);
    repeat (5) @(posedge clk);
    $display("  After 170 words: full=%b", nb_full);

    // NB-3: 读出2个包
    $display("--- NB-3: 读出2个包 ---");
    nb_read_pkt(9'd55, 16'hD001);
    nb_read_pkt(9'd55, 16'hD002);
    $display("  SC+NB NB-3 errors=%0d", err_nb_sc);

    // NB-4: 环形缓冲写读
    $display("--- NB-4: 读出后再写 (环形缓冲) ---");
    nb_write_pkt(9'd30, 16'hD005);
    nb_read_pkt(9'd55, 16'hD003);
    nb_read_pkt(9'd5, 16'hD004);
    nb_read_pkt(9'd30, 16'hD005);
    $display("  SC+NB NB-4 errors=%0d", err_nb_sc);

    // NB-5: 空FIFO后单包写读
    $display("--- NB-5: 空FIFO后单包写读 ---");
    nb_write_pkt(9'd1, 16'hDEAD);
    nb_read_pkt(9'd1, 16'hDEAD);
    $display("  SC+NB NB-5 errors=%0d", err_nb_sc);

    $display("=== SC+NB DONE: errors=%0d ===", err_nb_sc);
    test_done_cnt = test_done_cnt + 1;
  end

  // ============================================================
  // Test 3: DC+BLK (双时钟 + 块模式)
  // ============================================================
  initial begin : test_dc_blk
    integer i;
    @(posedge reset_l);
    repeat (5) @(posedge wclk_dc);

    $display("============================================");
    $display("=== Test 3: DC+BLK (双时钟+块模式) ===");
    $display("============================================");

    // BLK-1: 串行写3读3
    $display("--- BLK-1: 写3读3 ---");
    blk_dc_write_pkt(9'd8, 16'hA101);
    blk_dc_write_pkt(9'd16, 16'hA102);
    blk_dc_write_pkt(9'd4, 16'hA103);
    blk_dc_read_pkt(9'd8, 16'hA101);
    blk_dc_read_pkt(9'd16, 16'hA102);
    blk_dc_read_pkt(9'd4, 16'hA103);
    $display("  DC+BLK BLK-1 errors=%0d", err_blk_dc);

    // BLK-2: 写满16个块
    $display("--- BLK-2: 写满16个块 ---");
    for (i = 0; i < 16; i = i + 1) blk_dc_write_pkt(9'd10, i[PARA_WIDTH-1:0]);
    repeat (5) @(posedge wclk_dc);
    if (!blk_dc_full) $display("  WARN: full not asserted, full=%b", blk_dc_full);
    else $display("  full asserted OK");

    // BLK-3: 读出8个
    $display("--- BLK-3: 读出8个 ---");
    for (i = 0; i < 8; i = i + 1) blk_dc_read_pkt(9'd10, i[PARA_WIDTH-1:0]);
    $display("  DC+BLK BLK-3 errors=%0d", err_blk_dc);

    // BLK-4: 读完剩余8个
    $display("--- BLK-4: 读完剩余8个 ---");
    for (i = 8; i < 16; i = i + 1) blk_dc_read_pkt(9'd10, i[PARA_WIDTH-1:0]);
    $display("  DC+BLK BLK-4 errors=%0d", err_blk_dc);

    // BLK-5: 单word边界
    $display("--- BLK-5: 单word边界 ---");
    blk_dc_write_pkt(9'd1, 16'hBEEF);
    blk_dc_read_pkt(9'd1, 16'hBEEF);
    $display("  DC+BLK BLK-5 errors=%0d", err_blk_dc);

    $display("=== DC+BLK DONE: errors=%0d ===", err_blk_dc);
    test_done_cnt = test_done_cnt + 1;
  end

  // ============================================================
  // Test 4: DC+NB (双时钟 + 非块模式)
  // ============================================================
  initial begin : test_dc_nb
    integer i;
    @(posedge reset_l);
    repeat (5) @(posedge wclk_dc);

    $display("============================================");
    $display("=== Test 4: DC+NB (双时钟+非块模式) ===");
    $display("============================================");

    // NB-1: 串行写3读3
    $display("--- NB-1: 写3读3 ---");
    nb_dc_write_pkt(9'd7, 16'hC101);
    nb_dc_write_pkt(9'd20, 16'hC102);
    nb_dc_write_pkt(9'd3, 16'hC103);
    nb_dc_read_pkt(9'd7, 16'hC101);
    nb_dc_read_pkt(9'd20, 16'hC102);
    nb_dc_read_pkt(9'd3, 16'hC103);
    $display("  DC+NB NB-1 errors=%0d", err_nb_dc);

    // NB-2: 填充buffer
    $display("--- NB-2: 填充buffer (4包/170 words) ---");
    nb_dc_write_pkt(9'd55, 16'hD101);
    nb_dc_write_pkt(9'd55, 16'hD102);
    nb_dc_write_pkt(9'd55, 16'hD103);
    nb_dc_write_pkt(9'd5, 16'hD104);
    repeat (5) @(posedge wclk_dc);
    $display("  After 170 words: full=%b", nb_dc_full);

    // NB-3: 读出2个包
    $display("--- NB-3: 读出2个包 ---");
    nb_dc_read_pkt(9'd55, 16'hD101);
    nb_dc_read_pkt(9'd55, 16'hD102);
    $display("  DC+NB NB-3 errors=%0d", err_nb_dc);

    // NB-4: 环形缓冲写读
    $display("--- NB-4: 读出后再写 (环形缓冲) ---");
    nb_dc_write_pkt(9'd30, 16'hD105);
    nb_dc_read_pkt(9'd55, 16'hD103);
    nb_dc_read_pkt(9'd5, 16'hD104);
    nb_dc_read_pkt(9'd30, 16'hD105);
    $display("  DC+NB NB-4 errors=%0d", err_nb_dc);

    // NB-5: 空FIFO后单包写读
    $display("--- NB-5: 空FIFO后单包写读 ---");
    nb_dc_write_pkt(9'd1, 16'hDEAD);
    nb_dc_read_pkt(9'd1, 16'hDEAD);
    $display("  DC+NB NB-5 errors=%0d", err_nb_dc);

    $display("=== DC+NB DONE: errors=%0d ===", err_nb_dc);
    test_done_cnt = test_done_cnt + 1;
  end

  // ============================================================
  // 完成检测 & 汇总
  // ============================================================
  initial begin
    wait (test_done_cnt == 4);
    repeat (50) @(posedge clk);

    $display("============================================");
    $display("=== 4-COMBINATION REGRESSION SUMMARY ===");
    $display("============================================");
    $display("  SC+BLK  (单时钟+块模式):   errors=%0d", err_blk_sc);
    $display("  SC+NB   (单时钟+非块模式): errors=%0d", err_nb_sc);
    $display("  DC+BLK  (双时钟+块模式):   errors=%0d", err_blk_dc);
    $display("  DC+NB   (双时钟+非块模式): errors=%0d", err_nb_dc);
    $display("============================================");
    if (err_blk_sc + err_nb_sc + err_blk_dc + err_nb_dc == 0)
      $display("=== ALL 4 COMBINATIONS PASSED ===");
    else $display("=== FAILURES DETECTED ===");
    $display("============================================");
    // // $finish; (stripped) (stripped for sim)
  end

  // 超时保护
  initial begin
    #5000000;
    $display("=== TIMEOUT (5ms) ===");
    // // $finish; (stripped) (stripped for sim)
  end

  // 波形输出
  initial begin
    $dumpfile("tb_package_fifo_v2.vcd");
    $dumpvars(0, tb_package_fifo_v2);
  end
endmodule

// synthesis translate_on
