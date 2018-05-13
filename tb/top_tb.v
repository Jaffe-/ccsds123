`timescale 1ns/1ps

module top_tb;
`include "comp_params.v"
   parameter PERIOD = 10;

   parameter BUBBLES = 0;

   parameter OUT_BUBBLES = 1;

   reg clk, aresetn;
   reg [PIPELINES*D-1:0] in_tdata;
   reg         in_tvalid;

   wire        in_tready;
   wire [BUS_WIDTH-1:0] out_tdata;
   wire         out_tvalid;
   wire         out_last;
   reg         out_tready;

   ccsds123_top
     #(.PIPELINES(PIPELINES),
       .ISUNSIGNED(ISUNSIGNED),
       .D(D),
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
      .s_axis_tdata(in_tdata),
      .s_axis_tvalid(in_tvalid),
      .s_axis_tready(in_tready),
      .m_axis_tdata(out_tdata),
      .m_axis_tvalid(out_tvalid),
      .m_axis_tlast(out_last),
      .m_axis_tready(out_tready));

   always #(PERIOD/2) clk = ~clk;

   integer          i, iter;
   integer          in_count;
   integer          f_in, f_out;
   reg[200*8:0]    in_filename;
   integer         stalled_cycles, total_cycles;

   initial begin
      clk <= 1'b1;
      aresetn <= 1'b0;
      in_tdata <= 8'b0;
      in_tvalid <= 1'b0;

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

      for (iter = 0; iter < 2; iter = iter + 1) begin
         in_count = 0;
         stalled_cycles = 0;
         total_cycles = 0;
         $display("Starting iteration %0d", iter);
         $fseek(f_in, 0, 0);

         while (!$feof(f_in) && in_count < $ceil(NX*NY*NZ/$itor(PIPELINES))) begin
            total_cycles = total_cycles + 1;
            if (in_tready) begin
               if ((BUBBLES || $test$plusargs("BUBBLES")) && $urandom % 3 != 0) begin
                  in_tvalid <= 1'b0;
               end else begin
                  for (i = 0; i < PIPELINES; i = i + 1) begin
                     in_tdata[i*D     +: 8] <= $fgetc(f_in);
                     in_tdata[i*D + 8 +: 8] <= $fgetc(f_in);
                  end
                  in_tvalid <= 1'b1;
                  in_count = in_count + 1;
               end
            end else begin
               stalled_cycles = stalled_cycles + 1;
            end
            @(posedge clk);
         end
      end
      while (!(in_tvalid == 1'b1 && in_tready == 1'b1))
        @(posedge clk);

      $fclose(f_in);

      in_tvalid <= 1'b0;
   end;

   integer stall_cnt;

   // Simulate random stalling of output stream
   initial begin
      while (1) begin
         out_tready <= 1'b1;
         if (OUT_BUBBLES && $urandom % 40 == 0) begin
            out_tready <= 1'b0;
            for (stall_cnt = 0; stall_cnt < 20 + ($urandom % 20); stall_cnt = stall_cnt + 1) begin
               @(posedge clk);
            end
         end
         @(posedge clk);
      end
   end

   integer byte_idx, j;
   integer prev_done;
   integer out_cycles, out_tvalid_cycles;
   reg [200*8:0] out_filename;
   reg [200*8:0] out_dir;

   initial begin
      if (!$value$plusargs("OUT_DIR=%s", out_dir)) begin
         out_dir = ".";
      end
      for (j = 0; j < 2; j = j + 1) begin
         out_cycles = 0;
         out_tvalid_cycles = 0;
         $sformat(out_filename, "%0s/out_%0d.bin", out_dir, j);
         f_out = $fopen(out_filename, "wb");
         while (prev_done || (out_tready !== 1'b1 || out_tvalid !== 1'b1 || out_last !== 1'b1)) begin
            prev_done = 0;
            @(posedge clk);
            out_cycles = out_cycles + 1;
            if (out_tvalid && out_tready) begin
               out_tvalid_cycles = out_tvalid_cycles + 1;
               for (byte_idx = 0; byte_idx < BUS_WIDTH/8; byte_idx = byte_idx + 1) begin
                  $fwrite(f_out, "%c", out_tdata[byte_idx*8+:8]);
               end
            end
         end
         prev_done = 1;
         $display("Done with iteration %0d", j);
         $fclose(f_out);

      end
      $display("\n********************************************************************************");
      $display("Stalled %0d of %0d cycles (%f%%)", stalled_cycles, total_cycles, 100*stalled_cycles / $itor(total_cycles));
      $display("Output valid %0d of %0d cycles (%f%%)", out_tvalid_cycles, out_cycles, 100*out_tvalid_cycles / $itor(out_cycles));
      $display("********************************************************************************\n");
      $finish;
   end;
endmodule // top_tb
