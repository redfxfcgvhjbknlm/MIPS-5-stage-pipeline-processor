// =============================================================================
// Top-Level 5-Stage Pipelined MIPS Processor
// Stages: IF -> ID -> EX -> MEM -> WB
// Features: Full forwarding unit + Hazard detection unit
// =============================================================================

`timescale 1ns/1ps

module mips_top (
    input  wire        clk,
    input  wire        reset
);

    // -------------------------------------------------------------------------
    // Wire declarations between stages
    // -------------------------------------------------------------------------

    // IF/ID Pipeline Register outputs
    wire [31:0] ifid_pc4;
    wire [31:0] ifid_instr;

    // ID/EX Pipeline Register outputs
    wire [31:0] idex_pc4;
    wire [31:0] idex_rdata1, idex_rdata2;
    wire [31:0] idex_imm;
    wire [4:0]  idex_rs, idex_rt, idex_rd;
    wire [4:0]  idex_shamt;
    wire        idex_regdst, idex_alusrc, idex_branch;
    wire        idex_memread, idex_memwrite;
    wire        idex_regwrite, idex_memtoreg;
    wire [2:0]  idex_aluop;
    wire        idex_jump;

    // EX/MEM Pipeline Register outputs
    wire [31:0] exmem_aluresult;
    wire [31:0] exmem_rdata2;
    wire [4:0]  exmem_waddr;
    wire        exmem_zero;
    wire        exmem_branch, exmem_memread, exmem_memwrite;
    wire        exmem_regwrite, exmem_memtoreg;
    wire [31:0] exmem_branch_target;
    wire        exmem_jump;
    wire [31:0] exmem_jump_target;

    // MEM/WB Pipeline Register outputs
    wire [31:0] memwb_aluresult;
    wire [31:0] memwb_memdata;
    wire [4:0]  memwb_waddr;
    wire        memwb_regwrite, memwb_memtoreg;

    // Forwarding unit outputs
    wire [1:0]  forwardA, forwardB;

    // Hazard detection unit outputs
    wire        pc_write;
    wire        ifid_write;
    wire        ctrl_flush;   // insert bubble into ID/EX

    // Branch/Jump control
    wire        pcsrc;        // branch taken
    wire [31:0] pc_branch;
    wire [31:0] pc_jump;

    // WB stage write-back data
    wire [31:0] wb_data;

    // -------------------------------------------------------------------------
    // Stage instantiations
    // -------------------------------------------------------------------------

    assign pcsrc        = exmem_branch & exmem_zero;
    assign pc_branch    = exmem_branch_target;
    assign pc_jump      = exmem_jump_target;
    assign wb_data      = memwb_memtoreg ? memwb_memdata : memwb_aluresult;

    // IF Stage
    if_stage IF (
        .clk            (clk),
        .reset          (reset),
        .pc_write       (pc_write),
        .pcsrc          (pcsrc),
        .jump           (exmem_jump),
        .pc_branch      (pc_branch),
        .pc_jump        (pc_jump),
        .ifid_pc4       (ifid_pc4),
        .ifid_instr     (ifid_instr)
    );

    // ID Stage
    id_stage ID (
        .clk            (clk),
        .reset          (reset),
        .ifid_write     (ifid_write),
        .ctrl_flush     (ctrl_flush),
        .pcsrc          (pcsrc),
        .jump_flush     (exmem_jump),
        .ifid_pc4       (ifid_pc4),
        .ifid_instr     (ifid_instr),
        // WB write-back
        .wb_regwrite    (memwb_regwrite),
        .wb_waddr       (memwb_waddr),
        .wb_data        (wb_data),
        // ID/EX outputs
        .idex_pc4       (idex_pc4),
        .idex_rdata1    (idex_rdata1),
        .idex_rdata2    (idex_rdata2),
        .idex_imm       (idex_imm),
        .idex_rs        (idex_rs),
        .idex_rt        (idex_rt),
        .idex_rd        (idex_rd),
        .idex_shamt     (idex_shamt),
        .idex_regdst    (idex_regdst),
        .idex_alusrc    (idex_alusrc),
        .idex_branch    (idex_branch),
        .idex_memread   (idex_memread),
        .idex_memwrite  (idex_memwrite),
        .idex_regwrite  (idex_regwrite),
        .idex_memtoreg  (idex_memtoreg),
        .idex_aluop     (idex_aluop),
        .idex_jump      (idex_jump)
    );

    // Hazard Detection Unit
    hazard_unit HAZARD (
        .idex_memread   (idex_memread),
        .idex_rt        (idex_rt),
        .ifid_rs        (ifid_instr[25:21]),
        .ifid_rt        (ifid_instr[20:16]),
        .pc_write       (pc_write),
        .ifid_write     (ifid_write),
        .ctrl_flush     (ctrl_flush)
    );

    // Forwarding Unit
    forwarding_unit FWD (
        .idex_rs        (idex_rs),
        .idex_rt        (idex_rt),
        .exmem_regwrite (exmem_regwrite),
        .exmem_waddr    (exmem_waddr),
        .memwb_regwrite (memwb_regwrite),
        .memwb_waddr    (memwb_waddr),
        .forwardA       (forwardA),
        .forwardB       (forwardB)
    );

    // EX Stage
    ex_stage EX (
        .clk            (clk),
        .reset          (reset),
        .idex_pc4       (idex_pc4),
        .idex_rdata1    (idex_rdata1),
        .idex_rdata2    (idex_rdata2),
        .idex_imm       (idex_imm),
        .idex_rs        (idex_rs),
        .idex_rt        (idex_rt),
        .idex_rd        (idex_rd),
        .idex_shamt     (idex_shamt),
        .idex_regdst    (idex_regdst),
        .idex_alusrc    (idex_alusrc),
        .idex_branch    (idex_branch),
        .idex_memread   (idex_memread),
        .idex_memwrite  (idex_memwrite),
        .idex_regwrite  (idex_regwrite),
        .idex_memtoreg  (idex_memtoreg),
        .idex_aluop     (idex_aluop),
        .idex_jump      (idex_jump),
        // Forwarding
        .forwardA       (forwardA),
        .forwardB       (forwardB),
        .exmem_aluresult(exmem_aluresult),   // forward from EX/MEM
        .wb_data        (wb_data),            // forward from MEM/WB
        // EX/MEM outputs
        .exmem_aluresult_out   (exmem_aluresult),
        .exmem_rdata2          (exmem_rdata2),
        .exmem_waddr           (exmem_waddr),
        .exmem_zero            (exmem_zero),
        .exmem_branch          (exmem_branch),
        .exmem_memread         (exmem_memread),
        .exmem_memwrite        (exmem_memwrite),
        .exmem_regwrite        (exmem_regwrite),
        .exmem_memtoreg        (exmem_memtoreg),
        .exmem_branch_target   (exmem_branch_target),
        .exmem_jump            (exmem_jump),
        .exmem_jump_target     (exmem_jump_target)
    );

    // MEM Stage
    mem_stage MEM (
        .clk                (clk),
        .reset              (reset),
        .exmem_aluresult    (exmem_aluresult),
        .exmem_rdata2       (exmem_rdata2),
        .exmem_waddr        (exmem_waddr),
        .exmem_memread      (exmem_memread),
        .exmem_memwrite     (exmem_memwrite),
        .exmem_regwrite     (exmem_regwrite),
        .exmem_memtoreg     (exmem_memtoreg),
        // MEM/WB outputs
        .memwb_aluresult    (memwb_aluresult),
        .memwb_memdata      (memwb_memdata),
        .memwb_waddr        (memwb_waddr),
        .memwb_regwrite     (memwb_regwrite),
        .memwb_memtoreg     (memwb_memtoreg)
    );

    // WB stage is combinational (handled by wb_data assignment above)

endmodule
