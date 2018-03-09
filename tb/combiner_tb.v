`timescale 1ns/1ps

module combiner_tb;
   parameter N_WORDS = 4;
   parameter MAX_LENGTH = 48;
   parameter BLOCK_SIZE = 32;

   parameter LENGTH_BITS = $clog2(MAX_LENGTH);
   parameter PERIOD = 10;

   reg clk, aresetn;
   reg [N_WORDS*MAX_LENGTH-1:0] in_words;
   reg [N_WORDS*LENGTH_BITS-1:0]  in_lengths;
   reg                          in_valid;

   combiner
     #(.BLOCK_SIZE(BLOCK_SIZE),
       .N_WORDS(N_WORDS),
       .MAX_LENGTH(MAX_LENGTH))
   i_dut
     (.clk(clk),
      .aresetn(aresetn),
      .in_words(in_words),
      .in_lengths(in_lengths),
      .in_valid(in_valid));

   always #(PERIOD/2) clk = ~clk;

   initial begin
      clk <= 1'b0;
      aresetn <= 1'b0;
      in_words <= 0;
      in_lengths <= 0;
      in_valid <= 1'b0;

      $display("L BITS = %d", LENGTH_BITS);

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      in_words <= {48'hDDD000000000,
                   48'hCCCCCC000000,
                   48'hBBBBBBBBB000,
                   48'hAAAAAAAAAAAA};
      in_lengths <= {6'd12, 6'd24, 6'd36, 6'd48};
      in_valid <= 1'b1;
      @(posedge clk);
   end;
endmodule; // combiner_tb
