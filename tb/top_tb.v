`timescale 1ns/1ps

module top_tb;
`include "comp_params.v"
   parameter BUS_WIDTH = 64;

   parameter PERIOD = 10;

   parameter BUBBLES = 1;

   reg clk, aresetn;
   reg [D-1:0] s_axis_tdata;
   reg         s_axis_tvalid;

   wire        s_axis_tready;
   wire [BUS_WIDTH-1:0] res;
   wire         res_valid;
   wire         res_last;

   ccsds123_top
     #(.D(D),
       .NX(NX),
       .NY(NY),
       .NZ(NZ),
       .P(P),
       .R(R),
       .OMEGA(OMEGA),
       .TINC_LOG(TINC_LOG),
       .V_MIN(V_MIN),
       .V_MAX(V_MAX),
       .UMAX(UMAX),
       .COUNTER_SIZE(COUNTER_SIZE),
       .INITIAL_COUNT(INITIAL_COUNT),
       .KZ_PRIME(KZ_PRIME),
       .COL_ORIENTED(COL_ORIENTED),
       .REDUCED(REDUCED),
       .BUS_WIDTH(BUS_WIDTH))
   i_top
     (.clk(clk),
      .aresetn(aresetn),
      .s_axis_tdata(s_axis_tdata),
      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .out_data(res),
      .out_valid(res_valid),
      .out_last(res_last));

   always #(PERIOD/2) clk = ~clk;

   integer          i, wr_i;
   integer          f_in, f_out;
   reg[200*8:0]    in_filename;

   initial begin
      clk <= 1'b0;
      aresetn <= 1'b0;
      s_axis_tdata <= 8'b0;
      s_axis_tvalid <= 1'b0;

      repeat(4) @(posedge clk);
      aresetn <= 1'b1;

      if (!$value$plusargs("IN_FILENAME=%s", in_filename)) begin
         in_filename = "test.bin";
      end
      f_in = $fopen(in_filename, "rb");

      if (f_in == 0) begin
         $display("Failed to open input file %s", in_filename);
         $finish;
      end

      while (!$feof(f_in)) begin
         if (BUBBLES) begin
            while ($urandom % 3 != 0) begin
               s_axis_tdata <= 0;
               s_axis_tvalid <= 1'b0;
               @(posedge clk);
            end
         end
         s_axis_tdata[D/2-1:0] <= $fgetc(f_in);
         s_axis_tdata[D-1:D/2] <= $fgetc(f_in);
         s_axis_tvalid <= 1'b1;
         @(posedge clk);
      end;

      $fclose(f_in);

      s_axis_tvalid <= 1'b0;
   end;

   integer j;
   reg [200*8:0] out_filename;
   initial begin
      if (!$value$plusargs("OUT_FILENAME=%s", out_filename)) begin
         out_filename = "out.bin";
      end
      f_out = $fopen(out_filename, "wb");
      while (res_last !== 1'b1) begin
         @(posedge clk);
         if (res_valid) begin
            for (j = BUS_WIDTH/8-1; j >= 0; j = j - 1) begin
               $fwrite(f_out, "%c", res[j*8+:8]);
            end
         end
      end
      $display("Done.\n");
      $fclose(f_out);
      $finish;
   end;
endmodule // top_tb
