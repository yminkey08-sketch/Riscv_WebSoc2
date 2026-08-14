// xpm_memory_sdpram_sim.v — Behavioral model for Xilinx XPM Simple Dual-Port RAM
// Write on port A, read on port B. For Verilator simulation.

module xpm_memory_sdpram #(
    parameter integer MEMORY_SIZE            = 2048,
    parameter          MEMORY_PRIMITIVE       = "auto",
    parameter          CLOCKING_MODE          = "common_clock",
    parameter          ECC_MODE               = "no_ecc",
    parameter          MEMORY_INIT_FILE       = "none",
    parameter          MEMORY_INIT_PARAM      = "",
    parameter integer  USE_MEM_INIT           = 0,
    parameter          WAKEUP_TIME            = "disable_sleep",
    parameter integer  AUTO_SLEEP_TIME        = 0,
    parameter integer  MESSAGE_CONTROL        = 0,
    parameter integer  USE_EMBEDDED_CONSTRAINT = 0,
    parameter          MEMORY_OPTIMIZATION     = "true",
    parameter integer  CASCADE_HEIGHT          = 0,
    parameter          RAM_DECOMP              = "auto",
    parameter integer  SIM_ASSERT_CHK          = 0,
    parameter integer  WRITE_PROTECT           = 1,
    parameter integer  IGNORE_INIT_SYNTH       = 0,
    // Port A (write)
    parameter integer  WRITE_DATA_WIDTH_A = 32,
    parameter integer  BYTE_WRITE_WIDTH_A = 32,
    parameter integer  ADDR_WIDTH_A       = 10,
    parameter          WRITE_MODE_A       = "read_first",
    parameter          RST_MODE_A         = "SYNC",
    // Port B (read)
    parameter integer  READ_DATA_WIDTH_B  = 32,
    parameter integer  ADDR_WIDTH_B       = 10,
    parameter          READ_RESET_VALUE_B = "0",
    parameter integer  READ_LATENCY_B     = 1,
    parameter          WRITE_MODE_B       = "no_change",
    parameter          RST_MODE_B         = "SYNC"
) (
    input  wire                                  sleep,
    input  wire                                  clka,
    input  wire                                  rsta,
    input  wire                                  ena,
    input  wire                                  regcea,
    input  wire [BYTE_WRITE_WIDTH_A/8-1:0]       wea,
    input  wire [ADDR_WIDTH_A-1:0]               addra,
    input  wire [WRITE_DATA_WIDTH_A-1:0]         dina,
    input  wire                                  injectsbiterra,
    input  wire                                  injectdbiterra,
    input  wire                                  clkb,
    input  wire                                  rstb,
    input  wire                                  enb,
    input  wire                                  regceb,
    input  wire [ADDR_WIDTH_B-1:0]               addrb,
    output reg  [READ_DATA_WIDTH_B-1:0]          doutb,
    // Additional Xilinx-specific ports (unused in simulation)
    input  wire                                  clocken2,
    input  wire                                  clocken3,
    input  wire                                  aclr0,
    input  wire                                  aclr1,
    input  wire                                  addressstall_a,
    input  wire                                  addressstall_b,
    input  wire [BYTE_WRITE_WIDTH_A/8-1:0]       byteena_a
);

    localparam MAX_WIDTH = (WRITE_DATA_WIDTH_A > READ_DATA_WIDTH_B) ?
                            WRITE_DATA_WIDTH_A : READ_DATA_WIDTH_B;
    localparam DEPTH = 1 << ADDR_WIDTH_A;

    reg [MAX_WIDTH-1:0] mem [0:DEPTH-1];
    integer _i_;

    initial begin
        for (_i_ = 0; _i_ < DEPTH; _i_ = _i_ + 1) mem[_i_] = 0;
    end

    // Port A: write (no addressstall check - unconnected in RTL)
    always @(posedge clka) begin
        if (ena && |wea) begin
            mem[addra] <= dina;
        end
    end

    // Port B: read
    generate
        if (READ_LATENCY_B >= 1) begin : gen_doutb_reg
            always @(posedge clkb) begin
                if (enb && regceb) begin
                    if (rstb)
                        doutb <= READ_RESET_VALUE_B;
                    else
                        doutb <= mem[addrb];
                end
            end
        end else begin : gen_doutb_comb
            always @(*) begin
                doutb = mem[addrb];
            end
        end
    endgenerate

endmodule
