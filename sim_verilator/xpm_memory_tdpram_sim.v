// xpm_memory_tdpram_sim.v — Behavioral model for Verilator simulation
// Dual-mode firmware loading:
//   1. If firmware.hex exists: load into ALL banks (original behavior, for minimal tests)
//   2. Else if firmware_bankN.hex exists: load per-bank (for full TCP/HTTP firmware)

module xpm_memory_tdpram #(
    parameter integer MEMORY_SIZE            = 2048,
    parameter          MEMORY_PRIMITIVE       = "auto",
    parameter          CLOCKING_MODE          = "common_clock",
    parameter          ECC_MODE               = "no_ecc",
    parameter          ECC_TYPE               = "NONE",
    parameter          ECC_BIT_RANGE          = "[7:0]",
    parameter          MEMORY_INIT_FILE       = "none",
    parameter          MEMORY_INIT_PARAM      = "",
    parameter integer  USE_MEM_INIT           = 1,
    parameter integer  USE_MEM_INIT_MMI       = 0,
    parameter          WAKEUP_TIME            = "disable_sleep",
    parameter integer  AUTO_SLEEP_TIME        = 0,
    parameter integer  MESSAGE_CONTROL        = 0,
    parameter integer  USE_EMBEDDED_CONSTRAINT = 0,
    parameter          MEMORY_OPTIMIZATION     = "true",
    parameter integer  CASCADE_HEIGHT          = 0,
    parameter          RAM_DECOMP              = "auto",
    parameter integer  SIM_ASSERT_CHK          = 0,
    parameter integer  width_byteena_a         = 1,
    parameter integer  width_byteena_b         = 1,
    parameter integer  WRITE_PROTECT           = 1,
    parameter integer  IGNORE_INIT_SYNTH       = 0,
    parameter integer  WRITE_DATA_WIDTH_A = 32,
    parameter integer  READ_DATA_WIDTH_A  = 32,
    parameter integer  BYTE_WRITE_WIDTH_A = 32,
    parameter integer  ADDR_WIDTH_A       = 10,
    parameter          READ_RESET_VALUE_A = "0",
    parameter integer  READ_LATENCY_A     = 2,
    parameter          WRITE_MODE_A       = "no_change",
    parameter          RST_MODE_A         = "SYNC",
    parameter integer  WRITE_DATA_WIDTH_B = 32,
    parameter integer  READ_DATA_WIDTH_B  = 32,
    parameter integer  BYTE_WRITE_WIDTH_B = 32,
    parameter integer  ADDR_WIDTH_B       = 10,
    parameter          READ_RESET_VALUE_B = "0",
    parameter integer  READ_LATENCY_B     = 2,
    parameter          WRITE_MODE_B       = "no_change",
    parameter          RST_MODE_B         = "SYNC"
) ( /* all ports same as original — omitted for brevity but present */
    input  wire sleep, input wire clka, input wire rsta, input wire ena, input wire regcea,
    input  wire [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0] wea,
    input  wire [ADDR_WIDTH_A-1:0] addra,
    input  wire [WRITE_DATA_WIDTH_A-1:0] dina,
    input  wire injectsbiterra, injectdbiterra,
    output reg  [READ_DATA_WIDTH_A-1:0] douta,
    output wire sbiterra, dbiterra,
    input  wire clkb, rstb, enb, regceb,
    input  wire [WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-1:0] web,
    input  wire [ADDR_WIDTH_B-1:0] addrb,
    input  wire [WRITE_DATA_WIDTH_B-1:0] dinb,
    input  wire injectsbiterrb, injectdbiterrb,
    output reg  [READ_DATA_WIDTH_B-1:0] doutb,
    output wire sbiterrb, dbiterrb,
    input  wire clocken2, clocken3, aclr0, aclr1,
    input  wire addressstall_a, addressstall_b,
    input  wire [BYTE_WRITE_WIDTH_A/8-1:0] byteena_a,
    input  wire [BYTE_WRITE_WIDTH_B/8-1:0] byteena_b
);

    assign sbiterra=0; assign dbiterra=0; assign sbiterrb=0; assign dbiterrb=0;

    localparam MAX_WIDTH = (WRITE_DATA_WIDTH_A > WRITE_DATA_WIDTH_B) ?
                            WRITE_DATA_WIDTH_A : WRITE_DATA_WIDTH_B;
    localparam DEPTH = MEMORY_SIZE / 8;
    reg [MAX_WIDTH-1:0] mem [0:DEPTH-1];

    integer _i_, _fd_, _w_, _bank_, _j_, _k_, _rd_, _nd_;
    reg [1023:0] _ipath_;
    reg [7:0] _dgs_ [0:7];
    reg [7:0] _c_;
    reg [255:0] _fn_;

    initial begin
        for (_i_ = 0; _i_ < DEPTH; _i_ = _i_ + 1) mem[_i_] = 0;

        // Try firmware.hex first (backward compat)
        _fd_ = $fopen("firmware.hex", "r");
        if (_fd_) begin
            for (_i_ = 0; _i_ < DEPTH; _i_ = _i_ + 1) begin
                if (!$feof(_fd_)) _w_ = $fscanf(_fd_, "%h\n", mem[_i_]);
            end
            $fclose(_fd_);
            $display("XPM: Loaded firmware.hex mem[0]=%08h", mem[0]);
        end
        else if (ADDR_WIDTH_A >= 8) begin
            // No firmware.hex — try per-bank loading
            $sformat(_ipath_, "%m");
            _bank_ = 0;
            // Parse bank number from instance path
            for (_j_ = 0; _j_ < 1000; _j_ = _j_ + 1) begin
                _c_ = _ipath_[_j_*8+:8];
                if (_c_ == 91) begin // '['
                    _bank_ = 0;
                    for (_k_ = _j_ + 1; _k_ < 1024; _k_ = _k_ + 1) begin
                        _c_ = _ipath_[_k_*8+:8];
                        if (_c_ >= 48 && _c_ <= 57) _bank_ = _bank_ * 10 + (_c_ - 48);
                        else begin _k_ = 2048; end
                    end
                    _j_ = 2000;
                end else if (_c_ == 93) begin // ']' - reversed
                    _nd_ = 0;
                    for (_k_ = _j_ + 1; _k_ < 1024; _k_ = _k_ + 1) begin
                        _c_ = _ipath_[_k_*8+:8];
                        if (_c_ >= 48 && _c_ <= 57) begin
                            if (_nd_ < 8) begin _dgs_[_nd_] = _c_ - 48; _nd_ = _nd_ + 1; end
                        end else begin
                            for (_rd_ = _nd_ - 1; _rd_ >= 0; _rd_ = _rd_ - 1)
                                _bank_ = _bank_ * 10 + _dgs_[_rd_];
                            _k_ = 2048;
                        end
                    end
                    _j_ = 2000;
                end
            end
            $sformat(_fn_, "firmware_bank%0d.hex", _bank_);
            _fd_ = $fopen(_fn_, "r");
            if (_fd_) begin
                for (_i_ = 0; _i_ < DEPTH; _i_ = _i_ + 1) begin
                    if (!$feof(_fd_)) _w_ = $fscanf(_fd_, "%h\n", mem[_i_]);
                end
                $fclose(_fd_);
                if (_bank_ == 0)
                    $display("XPM: Loaded %s mem[0]=%08h", _fn_, mem[0]);
            end
        end
    end

    // Byte-enable-aware write. wea/web has one enable bit per BYTE_WRITE_WIDTH
    // group (port width WRITE_DATA_WIDTH/BYTE_WRITE_WIDTH); write each byte of
    // an enabled group. Correct for BYTE_WRITE_WIDTH 8/16/32.
    // (Old code `mem <= din` ignored byte enable → sb/sh corrupted adjacent bytes.)
    localparam _GPA_ = BYTE_WRITE_WIDTH_A / 8;                 // bytes per group (A)
    localparam _NGA_ = WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;  // num groups (A)
    localparam _GPB_ = BYTE_WRITE_WIDTH_B / 8;                 // bytes per group (B)
    localparam _NGB_ = WRITE_DATA_WIDTH_B / BYTE_WRITE_WIDTH_B;  // num groups (B)
    integer _ga_, _gb_, _ba_, _bb_;
    always @(posedge clka) begin
        if (ena)
            for (_ga_ = 0; _ga_ < _NGA_; _ga_ = _ga_ + 1)
                if (wea[_ga_])
                    for (_ba_ = 0; _ba_ < _GPA_; _ba_ = _ba_ + 1)
                        mem[addra][(_ga_*_GPA_ + _ba_)*8 +: 8] <= dina[(_ga_*_GPA_ + _ba_)*8 +: 8];
    end
    always @(posedge clka) begin if (ena && regcea) douta <= mem[addra]; end
    always @(posedge clkb) begin
        if (enb)
            for (_gb_ = 0; _gb_ < _NGB_; _gb_ = _gb_ + 1)
                if (web[_gb_])
                    for (_bb_ = 0; _bb_ < _GPB_; _bb_ = _bb_ + 1)
                        mem[addrb][(_gb_*_GPB_ + _bb_)*8 +: 8] <= dinb[(_gb_*_GPB_ + _bb_)*8 +: 8];
    end
    always @(posedge clkb) begin if (enb && regceb) doutb <= mem[addrb]; end

endmodule
