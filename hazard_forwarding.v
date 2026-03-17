// =============================================================================
// Hazard Detection Unit
// Detects load-use data hazard (LW followed immediately by dependent instr.)
// Action: stall PC + IF/ID, insert NOP bubble into ID/EX
// =============================================================================

module hazard_unit (
    input  wire        idex_memread,   // is the instr in EX a LW?
    input  wire [4:0]  idex_rt,        // destination of the LW
    input  wire [4:0]  ifid_rs,        // source registers of the instruction
    input  wire [4:0]  ifid_rt,        //   currently in the ID stage
    output reg         pc_write,       // 0 = stall PC
    output reg         ifid_write,     // 0 = hold IF/ID register
    output reg         ctrl_flush      // 1 = insert bubble (zero ctrl sigs)
);

    always @(*) begin
        // Default: no stall
        pc_write   = 1'b1;
        ifid_write = 1'b1;
        ctrl_flush = 1'b0;

        if (idex_memread &&
            ((idex_rt == ifid_rs) || (idex_rt == ifid_rt))) begin
            // Load-use hazard detected → stall one cycle
            pc_write   = 1'b0;
            ifid_write = 1'b0;
            ctrl_flush = 1'b1;
        end
    end

endmodule


// =============================================================================
// Forwarding Unit
// Handles EX-EX and MEM-EX forwarding to eliminate data hazards
// after the load-use stall has been resolved.
//
// forwardA / forwardB encoding:
//   00 = no forwarding  → use ID/EX register value
//   10 = EX/MEM forward → use ALU result from previous instruction
//   01 = MEM/WB forward → use write-back data from two instructions ago
// =============================================================================

module forwarding_unit (
    input  wire [4:0]  idex_rs,
    input  wire [4:0]  idex_rt,
    input  wire        exmem_regwrite,
    input  wire [4:0]  exmem_waddr,
    input  wire        memwb_regwrite,
    input  wire [4:0]  memwb_waddr,
    output reg  [1:0]  forwardA,
    output reg  [1:0]  forwardB
);

    always @(*) begin
        // ----- Forward A (first ALU source: rs) -----
        // Priority: EX/MEM > MEM/WB
        if (exmem_regwrite && (exmem_waddr != 5'b0) &&
            (exmem_waddr == idex_rs))
            forwardA = 2'b10;    // EX-EX forward
        else if (memwb_regwrite && (memwb_waddr != 5'b0) &&
                 (memwb_waddr == idex_rs))
            forwardA = 2'b01;    // MEM-EX forward
        else
            forwardA = 2'b00;    // no forward

        // ----- Forward B (second ALU source: rt) -----
        if (exmem_regwrite && (exmem_waddr != 5'b0) &&
            (exmem_waddr == idex_rt))
            forwardB = 2'b10;    // EX-EX forward
        else if (memwb_regwrite && (memwb_waddr != 5'b0) &&
                 (memwb_waddr == idex_rt))
            forwardB = 2'b01;    // MEM-EX forward
        else
            forwardB = 2'b00;    // no forward
    end

endmodule
