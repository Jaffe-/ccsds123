`timescale 1ns/1ps

module top_tb;
   parameter NX = 4;
   parameter NY = 4;
   parameter NZ = 16;
   parameter D = 16;
   parameter P = 4;
   parameter R = 32;
   parameter CZ = 7;
   parameter OMEGA = 10;

   // Encoder options
   parameter KZ_PRIME = 8;
   parameter COUNTER_SIZE = 8;
   parameter INITIAL_COUNT = 6;
   parameter UMAX = 9;

   parameter PERIOD = 10;

   parameter BUBBLES = 1;

   reg clk, aresetn;
   reg [D-1:0] s_axis_tdata;
   reg         s_axis_tvalid;

   wire        s_axis_tready;
   wire [D-1:0]  res;
   wire         res_valid;

   ccsds123_top
     #(.D(D),
       .NX(NX),
       .NY(NY),
       .NZ(NZ),
       .P(P),
       .R(R),
       .CZ(CZ),
       .OMEGA(OMEGA),
       .UMAX(UMAX),
       .COUNTER_SIZE(COUNTER_SIZE),
       .INITIAL_COUNT(INITIAL_COUNT),
       .KZ_PRIME(KZ_PRIME))
   i_top
     (.clk(clk),
      .aresetn(aresetn),
      .s_axis_tdata(s_axis_tdata),
      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .res(res),
      .res_valid(res_valid));

   integer          i, wr_i;
   integer          f_out;

   always #(PERIOD/2) clk = ~clk;

   initial begin
      clk <= 1'b0;
      aresetn <= 1'b0;
      s_axis_tdata <= 8'b0;
      s_axis_tvalid <= 1'b0;

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      for (i = 0; i < NX*NY*NZ; i = i + 1) begin
         if (BUBBLES) begin
            while ($urandom % 3 != 0) begin
               s_axis_tdata <= 0;
               s_axis_tvalid <= 1'b0;
               @(posedge clk);
            end
         end
         s_axis_tdata <= i;
         s_axis_tvalid <= 1'b1;
         @(posedge clk);
      end;

      s_axis_tvalid <= 1'b0;
   end;

   initial begin
      f_out = $fopen("output.txt","w");
      wr_i = 0;
      while (wr_i < NX*NY*NZ) begin
         @(posedge clk);
         if (res_valid) begin
            $fwrite(f_out, "%d\n", res);
            wr_i = wr_i + 1;
         end
      end
      $fclose(f_out);
   end;
endmodule // top_tb
