`timescale 1ns/1ps

module top_tb;
   parameter NX = 4;
   parameter NY = 4;
   parameter NZ = 16;
   parameter D = 8;
   parameter P = 4;
   parameter CZ = 7;
   parameter OMEGA = 10;
   parameter PERIOD = 10;

   reg clk, aresetn;
   reg [D-1:0] s_axis_tdata;
   reg         s_axis_tvalid;

   wire        s_axis_tready;
   wire [D:0]  res;
   wire        res_valid;

   ccsds123_top #(.D(D),
                  .NX(NX),
                  .NY(NY),
                  .NZ(NZ),
                  .P(P),
                  .CZ(CZ),
                  .OMEGA(OMEGA))
   i_top (
      .clk(clk),
      .aresetn(aresetn),
      .s_axis_tdata(s_axis_tdata),
      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .res(res),
      .res_valid(res_valid));

   integer          i;

   always #(PERIOD/2) clk = ~clk;

   initial begin
      clk <= 1'b0;
      aresetn <= 1'b0;
      s_axis_tdata <= 8'b0;
      s_axis_tvalid <= 1'b0;

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      for (i = 0; i < NX*NY*NZ; i = i + 1) begin
         s_axis_tdata <= i;
         s_axis_tvalid <= 1'b1;
         @(posedge clk);
      end;

      s_axis_tvalid <= 1'b0;
   end;
endmodule // top_tb
