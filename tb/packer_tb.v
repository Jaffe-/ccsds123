`timescale 1ns/1ps

module packer_tb;
   parameter BUS_WIDTH = 8;
   parameter MAX_IN_WIDTH = 8;

   parameter BUBBLES = 1;
   parameter PERIOD = 10;
   parameter MAX_ITER = 5;

   reg clk, aresetn;
   reg [MAX_IN_WIDTH-1:0] in_data;
   reg         in_valid;
   reg         in_last;
   reg [4:0] in_num_bits;

   wire        out_valid;
   wire        out_last;
   wire [BUS_WIDTH-1:0] out_data;

   packer_wrapper
     #(.BUS_WIDTH(BUS_WIDTH),
       .MAX_IN_WIDTH(MAX_IN_WIDTH))
   i_packer
     (.clk(clk),
      .aresetn(aresetn),
      .in_valid(in_valid),
      .in_last(in_last),
      .in_data(in_data),
      .in_num_bits(in_num_bits),
      .out_valid(out_valid),
      .out_last(out_last),
      .out_data(out_data));

   integer          i;

   always #(PERIOD/2) clk = ~clk;

   initial begin
      clk <= 1'b0;
      aresetn <= 1'b0;
      in_data <= 8'b0;
      in_num_bits <= 3'b0;
      in_valid <= 1'b0;
      in_last <= 1'b0;

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      for (i = 0; i < MAX_ITER; i = i + 1) begin
         if (BUBBLES) begin
            while ($urandom % 3 != 0) begin
               in_data <= 8'b0;
               in_num_bits <= 5'b0;
               in_valid <= 1'b0;
               @(posedge clk);
            end
         end
         in_valid <= 1'b1;
         in_data <= 8'b110011;
         in_num_bits <= 5'd6;
         if (i == MAX_ITER-1) begin
           in_last <= 1'b1;
         end
         @(posedge clk);
      end

      in_valid <= 1'b0;
      @(posedge clk);
   end;
endmodule // top_tb
