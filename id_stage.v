// =============================================================================
// ID Stage: Instruction Decode
// - Register File (32 x 32-bit, synchronous write / async read)
// - Control Unit
// - Sign Extender
// - ID/EX Pipeline Register
// =============================================================================

module id_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        ifid_write,      // stall signal (hold IF/ID reg when 0)
    input  wire        ctrl_flush,      // insert NOP bubble (load-use hazard)
    input  wire        pcsrc,           // flush on branch
    input  wire        jump_flush,      // flush on jump
    // From IF/ID register
    input  wire [31:0] ifid_pc4,
    input  wire [31:0] ifid_instr,
    // Write-back from WB stage
    input  wire        wb_regwrite,
    input  wire [4:0]  wb_waddr,
    input  wire [31:0] wb_data,
    // ID/EX outputs
    output reg  [31:0] idex_pc4,
    output reg  [31:0] idex_rdata1,
    output reg  [31:0] idex_rdata2,
    output reg  [31:0] idex_imm,
    output reg  [4:0]  idex_rs,
    output reg  [4:0]  idex_rt,
    output reg  [4:0]  idex_rd,
    output reg  [4:0]  idex_shamt,
    output reg         idex_regdst,
    output reg         idex_alusrc,
    output reg         idex_branch,
    output reg         idex_memread,
    output reg         idex_memwrite,
    output reg         idex_regwrite,
    output reg         idex_memtoreg,
    output reg  [2:0]  idex_aluop,
    output reg         idex_jump
);

    // -------------------------------------------------------------------------
    // Register File
    // -------------------------------------------------------------------------
    reg [31:0] regfile [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            regfile[i] = 32'b0;
    end

    // Synchronous write
    always @(posedge clk) begin
        if (wb_regwrite && wb_waddr != 5'b0)
            regfile[wb_waddr] <= wb_data;
    end

    // Asynchronous read (with write-through for same-cycle WB)
    wire [4:0] rs = ifid_instr[25:21];
    wire [4:0] rt = ifid_instr[20:16];

    wire [31:0] rdata1 = (wb_regwrite && wb_waddr == rs && rs != 0)
                         ? wb_data : regfile[rs];
    wire [31:0] rdata2 = (wb_regwrite && wb_waddr == rt && rt != 0)
                         ? wb_data : regfile[rt];

    // -------------------------------------------------------------------------
    // Sign Extender (16-bit immediate -> 32-bit)
    // -------------------------------------------------------------------------
    wire [31:0] sign_ext = {{16{ifid_instr[15]}}, ifid_instr[15:0]};

    // -------------------------------------------------------------------------
    // Control Unit
    // -------------------------------------------------------------------------
    wire [5:0] opcode = ifid_instr[31:26];
    wire [5:0] funct  = ifid_instr[5:0];

    reg  ctrl_regdst, ctrl_alusrc, ctrl_branch;
    reg  ctrl_memread, ctrl_memwrite;
    reg  ctrl_regwrite, ctrl_memtoreg;
    reg  [2:0] ctrl_aluop;
    reg  ctrl_jump;

    always @(*) begin
        // Default: NOP
        ctrl_regdst   = 0; ctrl_alusrc   = 0; ctrl_branch  = 0;
        ctrl_memread  = 0; ctrl_memwrite = 0;
        ctrl_regwrite = 0; ctrl_memtoreg = 0;
        ctrl_aluop    = 3'b000;
        ctrl_jump     = 0;

        case (opcode)
            6'b000000: begin  // R-type
                ctrl_regdst   = 1;
                ctrl_regwrite = 1;
                ctrl_aluop    = 3'b010;
            end
            6'b100011: begin  // LW
                ctrl_alusrc   = 1;
                ctrl_memread  = 1;
                ctrl_regwrite = 1;
                ctrl_memtoreg = 1;
                ctrl_aluop    = 3'b000;  // ADD
            end
            6'b101011: begin  // SW
                ctrl_alusrc   = 1;
                ctrl_memwrite = 1;
                ctrl_aluop    = 3'b000;  // ADD
            end
            6'b000100: begin  // BEQ
                ctrl_branch   = 1;
                ctrl_aluop    = 3'b001;  // SUB (to check equality)
            end
            6'b000101: begin  // BNE
                ctrl_branch   = 1;
                ctrl_aluop    = 3'b001;
            end
            6'b001000: begin  // ADDI
                ctrl_alusrc   = 1;
                ctrl_regwrite = 1;
                ctrl_aluop    = 3'b000;  // ADD
            end
            6'b001100: begin  // ANDI
                ctrl_alusrc   = 1;
                ctrl_regwrite = 1;
                ctrl_aluop    = 3'b011;  // AND
            end
            6'b001101: begin  // ORI
                ctrl_alusrc   = 1;
                ctrl_regwrite = 1;
                ctrl_aluop    = 3'b100;  // OR
            end
            6'b001010: begin  // SLTI
                ctrl_alusrc   = 1;
                ctrl_regwrite = 1;
                ctrl_aluop    = 3'b101;  // SLT
            end
            6'b000010: begin  // J (jump)
                ctrl_jump     = 1;
            end
            6'b000011: begin  // JAL
                ctrl_jump     = 1;
                ctrl_regwrite = 1;  // writes return addr to $ra
            end
            default: ; // NOP / undefined
        endcase
    end

    // -------------------------------------------------------------------------
    // Determine if we must insert a bubble
    // -------------------------------------------------------------------------
    wire flush = ctrl_flush | pcsrc | jump_flush;

    // -------------------------------------------------------------------------
    // ID/EX Pipeline Register
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            idex_pc4      <= 32'b0;
            idex_rdata1   <= 32'b0;
            idex_rdata2   <= 32'b0;
            idex_imm      <= 32'b0;
            idex_rs       <= 5'b0;
            idex_rt       <= 5'b0;
            idex_rd       <= 5'b0;
            idex_shamt    <= 5'b0;
            // Zero out all control signals (NOP bubble)
            idex_regdst   <= 0;
            idex_alusrc   <= 0;
            idex_branch   <= 0;
            idex_memread  <= 0;
            idex_memwrite <= 0;
            idex_regwrite <= 0;
            idex_memtoreg <= 0;
            idex_aluop    <= 3'b000;
            idex_jump     <= 0;
        end else begin
            idex_pc4      <= ifid_pc4;
            idex_rdata1   <= rdata1;
            idex_rdata2   <= rdata2;
            idex_imm      <= sign_ext;
            idex_rs       <= rs;
            idex_rt       <= rt;
            idex_rd       <= ifid_instr[15:11];
            idex_shamt    <= ifid_instr[10:6];
            idex_regdst   <= ctrl_regdst;
            idex_alusrc   <= ctrl_alusrc;
            idex_branch   <= ctrl_branch;
            idex_memread  <= ctrl_memread;
            idex_memwrite <= ctrl_memwrite;
            idex_regwrite <= ctrl_regwrite;
            idex_memtoreg <= ctrl_memtoreg;
            idex_aluop    <= ctrl_aluop;
            idex_jump     <= ctrl_jump;
        end
    end

endmodule
