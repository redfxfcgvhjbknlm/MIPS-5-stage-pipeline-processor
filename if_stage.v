// =============================================================================
// IF Stage: Instruction Fetch
// - Program Counter (PC)
// - Instruction Memory (256 words, word-addressed)
// - IF/ID Pipeline Register
// =============================================================================

module if_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        pc_write,       // from hazard unit (stall when 0)
    input  wire        pcsrc,          // branch taken
    input  wire        jump,           // jump instruction
    input  wire [31:0] pc_branch,      // branch target from EX/MEM
    input  wire [31:0] pc_jump,        // jump target from EX/MEM
    output reg  [31:0] ifid_pc4,       // PC+4
    output reg  [31:0] ifid_instr      // fetched instruction
);

    // Program Counter
    reg  [31:0] pc;
    wire [31:0] pc4 = pc + 32'd4;
    wire [31:0] pc_next;

    // Instruction Memory: 256 x 32-bit words
    reg [31:0] imem [0:255];

    // Load program (simulation only)
    initial begin
        $readmemh("program.hex", imem);
    end

    // PC next-value logic
    assign pc_next = jump   ? pc_jump   :
                     pcsrc  ? pc_branch :
                              pc4;

    // PC register
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'h0000_0000;
        else if (pc_write)
            pc <= pc_next;
    end

    // Instruction fetch
    wire [31:0] instr = imem[pc[9:2]];  // word-addressed (byte addr >> 2)

    // IF/ID Pipeline Register
    always @(posedge clk or posedge reset) begin
        if (reset || pcsrc || jump) begin
            // Flush on branch or jump taken
            ifid_pc4   <= 32'b0;
            ifid_instr <= 32'b0;  // NOP
        end else if (ifid_write) begin
            ifid_pc4   <= pc4;
            ifid_instr <= instr;
        end
        // else: stall – hold current values (ifid_write = 0)
    end

    // Expose ifid_write so the always block can use it
    // (driven by hazard unit, passed down from top)
    // Note: in a real instantiation this would be a port; included here for clarity
    wire ifid_write; // Must be connected from top – placeholder shown

endmodule
