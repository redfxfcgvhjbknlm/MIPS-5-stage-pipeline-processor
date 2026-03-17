// =============================================================================
// MEM Stage: Memory Access
// - Data Memory (256 words, byte-addressed, word-granularity R/W)
// - MEM/WB Pipeline Register
// =============================================================================

module mem_stage (
    input  wire        clk,
    input  wire        reset,
    // From EX/MEM register
    input  wire [31:0] exmem_aluresult,
    input  wire [31:0] exmem_rdata2,
    input  wire [4:0]  exmem_waddr,
    input  wire        exmem_memread,
    input  wire        exmem_memwrite,
    input  wire        exmem_regwrite,
    input  wire        exmem_memtoreg,
    // MEM/WB outputs
    output reg  [31:0] memwb_aluresult,
    output reg  [31:0] memwb_memdata,
    output reg  [4:0]  memwb_waddr,
    output reg         memwb_regwrite,
    output reg         memwb_memtoreg
);

    // Data Memory: 256 x 32-bit words
    reg [31:0] dmem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            dmem[i] = 32'b0;
    end

    // Memory read (asynchronous for simplicity; gate with memread)
    wire [31:0] mem_rdata = exmem_memread ? dmem[exmem_aluresult[9:2]] : 32'bx;

    // Memory write (synchronous)
    always @(posedge clk) begin
        if (exmem_memwrite)
            dmem[exmem_aluresult[9:2]] <= exmem_rdata2;
    end

    // MEM/WB Pipeline Register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            memwb_aluresult <= 32'b0;
            memwb_memdata   <= 32'b0;
            memwb_waddr     <= 5'b0;
            memwb_regwrite  <= 1'b0;
            memwb_memtoreg  <= 1'b0;
        end else begin
            memwb_aluresult <= exmem_aluresult;
            memwb_memdata   <= mem_rdata;
            memwb_waddr     <= exmem_waddr;
            memwb_regwrite  <= exmem_regwrite;
            memwb_memtoreg  <= exmem_memtoreg;
        end
    end

endmodule
