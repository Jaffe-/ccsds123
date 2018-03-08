`timescale 1ns/1ps

module combiner_tb;
   parameter N_WORDS = 4;
   parameter MAX_LENGTH = 20;
   parameter PERIOD = 10;

   reg clk, aresetn;
   reg [N_WORDS*MAX_LENGTH-1:0] in_words;
   reg [N_WORDS*5-1:0]                    in_lengths;
   reg                          in_valid;

   combiner
     #(.BLOCK_SIZE(64),
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

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      in_words <= {20'hAA000, 20'hB0000, 20'hCCC00, 20'hDDDD0};
      in_lengths <= {5'h8, 5'h4, 5'hC, 5'h10};
      in_valid <= 1'b1;
      @(posedge clk);
   end;
endmodule; // combiner_tb
