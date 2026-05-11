// ============================================================
// tb_cam_capture.v  –  Testbench for cam_capture module
//
// Two sub-tests:
//   [A]  enable = 0  --> NO writes (even with valid HREF/data)
//   [B]  enable = 1, SKIP_TOP_ROWS overridden to 0
//        --> 12 pixels assembled correctly from a 4x3 mini-frame
//
// We override SKIP_TOP_ROWS to 0 in the DUT.  In the real design
// the default value (2) hides the camera's blanking strip; turning
// it off here lets a small (4-pixel-wide) test still produce writes.
// ============================================================
`timescale 1ns/1ps

module tb_cam_capture;

    reg        pclk    = 0;
    reg        href    = 0;
    reg        vsync   = 0;
    reg [7:0]  din     = 0;
    reg        enable  = 0;

    wire [16:0] wr_addr;
    wire [11:0] wr_data;
    wire        wr_en;

    // DUT with SKIP_TOP_ROWS = 0 for simulation
    cam_capture #(.SKIP_TOP_ROWS(8'd0)) dut (
        .pclk    (pclk),
        .href    (href),
        .vsync   (vsync),
        .din     (din),
        .enable  (enable),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .wr_en   (wr_en)
    );

    // 24 MHz PCLK  (period ~ 41.67 ns -> use 42 ns)
    always #21 pclk = ~pclk;

    // Task: send one RGB565 pixel as two bytes
    task send_pixel;
        input [4:0] r;
        input [5:0] g;
        input [4:0] b;
        reg   [15:0] pixel;
        begin
            pixel = {r, g, b};
            din = pixel[15:8];
            @(posedge pclk); #1;
            din = pixel[7:0];
            @(posedge pclk); #1;
        end
    endtask

    // Task: drive one row of n_pix pixels
    task send_row;
        input integer n_pix;
        input [4:0] r;
        input [5:0] g;
        input [4:0] b;
        integer j;
        begin
            href = 1;
            for (j = 0; j < n_pix; j = j + 1)
                send_pixel(r, g, b);
            href = 0;
            @(posedge pclk); @(posedge pclk); // gap between rows
        end
    endtask

    // Tally writes
    integer pixel_cnt = 0;
    always @(posedge pclk) begin
        if (wr_en) begin
            pixel_cnt <= pixel_cnt + 1;
            $display("WRITE  cnt=%0d  addr=%0d  rgb=%03h  at %0t",
                     pixel_cnt, wr_addr, wr_data, $time);
        end
    end

    initial begin
        $dumpfile("tb_cam_capture.vcd");
        $dumpvars(0, tb_cam_capture);

        // ---- Frame start ----
        vsync = 1;
        repeat(4) @(posedge pclk);
        vsync = 0;
        repeat(2) @(posedge pclk);

        // ===== [A]  enable = 0  -- must produce NO writes =====
        $display("\n[A] enable=0  -- expect 0 writes");
        enable = 0;
        send_row(4, 5'd31, 6'd0,  5'd0);  // RED
        send_row(4, 5'd0,  6'd63, 5'd0);  // GREEN
        send_row(4, 5'd0,  6'd0,  5'd31); // BLUE
        if (pixel_cnt == 0)
            $display("PASS [A]: 0 writes while enable=0");
        else
            $display("FAIL [A]: %0d writes while enable=0", pixel_cnt);

        // ===== [B]  enable = 1  -- expect 12 writes (4x3 frame) =====
        $display("\n[B] enable=1  -- expect 12 writes");
        enable = 1;
        // restart frame
        vsync = 1;
        repeat(4) @(posedge pclk);
        vsync = 0;
        repeat(2) @(posedge pclk);
        pixel_cnt = 0;

        send_row(4, 5'd31, 6'd0,  5'd0);  // RED   row
        send_row(4, 5'd0,  6'd63, 5'd0);  // GREEN row
        send_row(4, 5'd0,  6'd0,  5'd31); // BLUE  row

        repeat(10) @(posedge pclk);

        if (pixel_cnt == 12)
            $display("PASS [B]: captured %0d pixels (expected 12)", pixel_cnt);
        else
            $display("FAIL [B]: captured %0d pixels (expected 12)", pixel_cnt);

        $finish;
    end

endmodule
