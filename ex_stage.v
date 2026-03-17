// =============================================================================
// EX Stage: Execute
// - Forwarding MUXes (2x3-to-1)
// - ALU Control
// - ALU (32-bit)
// - EX/MEM Pipeline Register
// =============================================================================

module ex_stage (
    input  wire        clk,
    input  wire        reset,
    // From ID/EX register
    input  wire [31:0] idex_pc4,
    input  wire [31:0] idex_rdata1,
    input  wire [31:0] idex_rdata2,
    input  wire [31:0] idex_imm,
    input  wire [4:0]  idex_rs,
    input  wire [4:0]  idex_rt,
    input  wire [4:0]  idex_rd,
    input  wire [4:0]  idex_shamt,
    input  wire        idex_regdst,
    input  wire        idex_alusrc,
    input  wire        idex_branch,
    input  wire        idex_memread,
    input  wire        idex_memwrite,
    input  wire        idex_regwrite,
    input  wire        idex_memtoreg,
    input  wire [2:0]  idex_aluop,
    input  wire        idex_jump,
    // Forwarding control
    input  wire [1:0]  forwardA,
    input  wire [1:0]  forwardB,
    input  wire [31:0] exmem_aluresult,  // EX/MEM ALU result (forward)
    input  wire [31:0] wb_data,          // MEM/WB write-back data (forward)
    // EX/MEM Pipeline Register outputs
    output reg  [31:0] exmem_aluresult_out,
    output reg  [31:0] exmem_rdata2,
    output reg  [4:0]  exmem_waddr,
    output reg         exmem_zero,
    output reg         exmem_branch,
    output reg         exmem_memread,
    output reg         exmem_memwrite,
    output reg         exmem_regwrite,
    output reg         exmem_memtoreg,
    output reg  [31:0] exmem_branch_target,
    output reg         exmem_jump,
    output reg  [31:0] exmem_jump_target
);

    // -------------------------------------------------------------------------
    // Forwarding MUXes
    // forwardA/B: 00 = no forward (ID/EX), 01 = from MEM/WB, 10 = from EX/MEM
    // -------------------------------------------------------------------------
    reg [31:0] alu_inA, alu_inB_pre;

    always @(*) begin
        case (forwardA)
            2'b10:   alu_inA = exmem_aluresult;
            2'b01:   alu_inA = wb_data;
            default: alu_inA = idex_rdata1;
        endcase
    end

    always @(*) begin
        case (forwardB)
            2'b10:   alu_inB_pre = exmem_aluresult;
            2'b01:   alu_inB_pre = wb_data;
            default: alu_inB_pre = idex_rdata2;
        endcase
    end

    // ALU second operand: register or sign-extended immediate
    wire [31:0] alu_inB = idex_alusrc ? idex_imm : alu_inB_pre;

    // -------------------------------------------------------------------------
    // ALU Control
    // aluop: 000=ADD, 001=SUB, 010=R-type(use funct), 011=AND, 100=OR, 101=SLT
    // -------------------------------------------------------------------------
    wire [5:0] funct = idex_imm[5:0];
    reg  [3:0] alu_ctrl;

    always @(*) begin
        case (idex_aluop)
            3'b000: alu_ctrl = 4'b0010; // ADD  (LW/SW/ADDI)
            3'b001: alu_ctrl = 4'b0110; // SUB  (BEQ/BNE)
            3'b011: alu_ctrl = 4'b0000; // AND  (ANDI)
            3'b100: alu_ctrl = 4'b0001; // OR   (ORI)
            3'b101: alu_ctrl = 4'b0111; // SLT  (SLTI)
            3'b010: begin               // R-type: decode funct
                case (funct)
                    6'b100000: alu_ctrl = 4'b0010; // ADD
                    6'b100010: alu_ctrl = 4'b0110; // SUB
                    6'b100100: alu_ctrl = 4'b0000; // AND
                    6'b100101: alu_ctrl = 4'b0001; // OR
                    6'b100110: alu_ctrl = 4'b0101; // XOR
                    6'b101010: alu_ctrl = 4'b0111; // SLT
                    6'b000000: alu_ctrl = 4'b1000; // SLL
                    6'b000010: alu_ctrl = 4'b1001; // SRL
                    6'b000011: alu_ctrl = 4'b1010; // SRA
                    6'b100111: alu_ctrl = 4'b1011; // NOR
                    default:   alu_ctrl = 4'b0010;
                endcase
            end
            default: alu_ctrl = 4'b0010;
        endcase
    end

    // -------------------------------------------------------------------------
    // ALU
    // -------------------------------------------------------------------------
    reg  [31:0] alu_result;
    reg         alu_zero;

    always @(*) begin
        alu_zero = 1'b0;
        case (alu_ctrl)
            4'b0000: alu_result = alu_inA & alu_inB;              // AND
            4'b0001: alu_result = alu_inA | alu_inB;              // OR
            4'b0010: alu_result = alu_inA + alu_inB;              // ADD
            4'b0101: alu_result = alu_inA ^ alu_inB;              // XOR
            4'b0110: alu_result = alu_inA - alu_inB;              // SUB
            4'b0111: alu_result = ($signed(alu_inA) < $signed(alu_inB)) ? 32'd1 : 32'd0; // SLT
            4'b1000: alu_result = alu_inB << idex_shamt;          // SLL
            4'b1001: alu_result = alu_inB >> idex_shamt;          // SRL
            4'b1010: alu_result = $signed(alu_inB) >>> idex_shamt;// SRA
            4'b1011: alu_result = ~(alu_inA | alu_inB);           // NOR
            default: alu_result = 32'b0;
        endcase
        alu_zero = (alu_result == 32'b0);
    end

    // -------------------------------------------------------------------------
    // Register destination MUX: rd (R-type) or rt (I-type)
    // -------------------------------------------------------------------------
    wire [4:0] waddr = idex_regdst ? idex_rd : idex_rt;

    // -------------------------------------------------------------------------
    // Branch & Jump target computation
    // -------------------------------------------------------------------------
    wire [31:0] branch_target = idex_pc4 + {idex_imm[29:0], 2'b00};
    wire [31:0] jump_target   = {idex_pc4[31:28], idex_imm[25:0], 2'b00};

    // -------------------------------------------------------------------------
    // EX/MEM Pipeline Register
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exmem_aluresult_out  <= 32'b0;
            exmem_rdata2         <= 32'b0;
            exmem_waddr          <= 5'b0;
            exmem_zero           <= 1'b0;
            exmem_branch         <= 1'b0;
            exmem_memread        <= 1'b0;
            exmem_memwrite       <= 1'b0;
            exmem_regwrite       <= 1'b0;
            exmem_memtoreg       <= 1'b0;
            exmem_branch_target  <= 32'b0;
            exmem_jump           <= 1'b0;
            exmem_jump_target    <= 32'b0;
        end else begin
            exmem_aluresult_out  <= alu_result;
            exmem_rdata2         <= alu_inB_pre;  // unforwarded rt for SW
            exmem_waddr          <= waddr;
            exmem_zero           <= alu_zero;
            exmem_branch         <= idex_branch;
            exmem_memread        <= idex_memread;
            exmem_memwrite       <= idex_memwrite;
            exmem_regwrite       <= idex_regwrite;
            exmem_memtoreg       <= idex_memtoreg;
            exmem_branch_target  <= branch_target;
            exmem_jump           <= idex_jump;
            exmem_jump_target    <= jump_target;
        end
    end

endmodule
