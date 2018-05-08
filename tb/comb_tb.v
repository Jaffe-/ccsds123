`timescale 1ns/1ps

module comb_tb;
   parameter BLOCK_SIZE = 64;
   parameter N_WORDS = 4;
   parameter MAX_LENGTH = 48;

   parameter PERIOD = 10;

   reg clk, aresetn;
   reg [N_WORDS*MAX_LENGTH-1:0] in_words;
   reg [N_WORDS*7-1:0]          in_lengths;
   reg                          in_valid;
   reg                          in_last;

   packer
     #(.BLOCK_SIZE(BLOCK_SIZE),
       .N_WORDS(N_WORDS),
       .MAX_LENGTH(MAX_LENGTH),
       .N_WORDS_PER_CHAIN(1))
   dut
     (.clk(clk),
      .aresetn(aresetn),
      .in_words(in_words),
      .in_lengths(in_lengths),
      .in_valid(in_valid),
      .in_last(in_last),
      .out_ready(1'b1));

   always #(PERIOD/2) clk = ~clk;

   initial begin
      clk <= 1'b1;
      aresetn <= 1'b0;
      in_words <= 0;
      in_lengths <= 0;
      in_valid <= 1'b0;
      in_last <= 1'b0;

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      in_words <= {48'h444444000000,
                   48'h333333000000,
                   48'h222222220000,
                   48'h111111111111};
      in_lengths <= {7'd24, 7'd24, 7'd32, 7'd48};
      in_valid <= 1'b1;
      @(posedge clk);
      in_words <= {48'h800000000000,
                   48'h770000000000,
                   48'h666600000000,
                   48'h555555000000};
      in_lengths <= {7'd4, 7'd8, 7'd16, 7'd24};
      @(posedge clk);
      in_words <= {48'hCCCCCC000000,
                   48'hBBBBBBBBBB00,
                   48'hAAAAAAAA0000,
                   48'h999999999999};
      in_lengths <= {7'd24, 7'd40, 7'd32, 7'd48};
      in_last <= 1'b1;
      @(posedge clk);

      in_valid <= 1'b0;
   end;
endmodule // top_tb
