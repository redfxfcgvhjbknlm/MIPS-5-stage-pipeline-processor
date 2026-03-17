// =============================================================================
// Testbench: 5-Stage Pipelined MIPS Processor
//
// Test program (assembled into program.hex):
//
//   # Test forwarding (EX-EX and MEM-EX)
//   addi $t0, $zero, 10      # $t0 = 10
//   addi $t1, $zero, 20      # $t1 = 20
//   add  $t2, $t0, $t1       # $t2 = 30  (EX-EX forward from $t0, $t1)
//   sub  $t3, $t2, $t0       # $t3 = 20  (EX-EX forward from $t2)
//
//   # Test load-use stall
//   sw   $t2, 0($zero)       # mem[0] = 30
//   lw   $t4, 0($zero)       # $t4 = 30  (load from mem[0])
//   add  $t5, $t4, $t1       # $t5 = 50  (MEM-EX forward after LW stall)
//
//   # Test branch
//   beq  $t0, $t0, +1        # branch taken (skip next)
//   addi $t6, $zero, 99      # SKIPPED
//   addi $t7, $zero, 7       # $t7 = 7   (executed after branch)
// =============================================================================

`timescale 1ns/1ps

module mips_tb;

    reg clk, reset;

    // Instantiate DUT
    mips_top DUT (
        .clk   (clk),
        .reset (reset)
    );

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Create the test program HEX file
    initial begin
        // Write assembled MIPS instructions as 32-bit hex, one per line
        // Each line: hex representation of the 32-bit instruction word
        $writememh("program.hex", '{
            // addi $t0, $zero, 10  →  001000 00000 01000 0000000000001010
            32'h2008000A,
            // addi $t1, $zero, 20  →  001000 00000 01001 0000000000010100
            32'h20090014,
            // add  $t2, $t0, $t1  →  000000 01000 01001 01010 00000 100000
            32'h01095020,
            // sub  $t3, $t2, $t0  →  000000 01010 01000 01011 00000 100010
            32'h014A5822,
            // sw   $t2, 0($zero)  →  101011 00000 01010 0000000000000000
            32'hAC0A0000,
            // lw   $t4, 0($zero)  →  100011 00000 01100 0000000000000000
            32'h8C0C0000,
            // add  $t5, $t4, $t1  →  000000 01100 01001 01101 00000 100000
            32'h01896820,
            // beq  $t0, $t0, 1    →  000100 01000 01000 0000000000000001
            32'h11080001,
            // addi $t6, $zero, 99 →  001000 00000 01110 0000000001100011
            32'h200E0063,
            // addi $t7, $zero, 7  →  001000 00000 01111 0000000000000111
            32'h200F0007,
            // nop  (end of program)
            32'h00000000,
            32'h00000000,
            32'h00000000,
            32'h00000000
        });
    end

    // Simulation
    initial begin
        $dumpfile("mips_pipeline.vcd");
        $dumpvars(0, mips_tb);

        // Reset for 2 cycles
        reset = 1;
        @(posedge clk); @(posedge clk);
        reset = 0;

        // Run for 40 cycles
        repeat(40) @(posedge clk);

        // Display register file contents
        $display("=== Register File After Execution ===");
        $display("$t0 (r8)  = %0d (expect 10)",  DUT.ID.regfile[8]);
        $display("$t1 (r9)  = %0d (expect 20)",  DUT.ID.regfile[9]);
        $display("$t2 (r10) = %0d (expect 30)",  DUT.ID.regfile[10]);
        $display("$t3 (r11) = %0d (expect 20)",  DUT.ID.regfile[11]);
        $display("$t4 (r12) = %0d (expect 30)",  DUT.ID.regfile[12]);
        $display("$t5 (r13) = %0d (expect 50)",  DUT.ID.regfile[13]);
        $display("$t6 (r14) = %0d (expect 0, branch skipped)", DUT.ID.regfile[14]);
        $display("$t7 (r15) = %0d (expect 7)",   DUT.ID.regfile[15]);

        // Check pass/fail
        if (DUT.ID.regfile[8]  == 32'd10 &&
            DUT.ID.regfile[9]  == 32'd20 &&
            DUT.ID.regfile[10] == 32'd30 &&
            DUT.ID.regfile[11] == 32'd20 &&
            DUT.ID.regfile[12] == 32'd30 &&
            DUT.ID.regfile[13] == 32'd50 &&
            DUT.ID.regfile[14] == 32'd0  &&
            DUT.ID.regfile[15] == 32'd7)
            $display("PASS: All register values correct!");
        else
            $display("FAIL: Some register values are incorrect.");

        $finish;
    end

    // Cycle-by-cycle pipeline trace
    always @(posedge clk) begin
        if (!reset) begin
            $display("Cycle %0t | PC=%h | IF/ID=%h | FwdA=%b FwdB=%b | ctrl_flush=%b",
                $time,
                DUT.IF.pc,
                DUT.ifid_instr,
                DUT.FWD.forwardA,
                DUT.FWD.forwardB,
                DUT.HAZARD.ctrl_flush
            );
        end
    end

endmodule
