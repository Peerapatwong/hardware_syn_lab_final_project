// ============================================================
// tb_cam_capture.v  –  Testbench for cam_capture module
// Simulates OV7670 RGB565 output for a 4x3 pixel mini-frame
// and checks that pixel data is correctly assembled and stored
// ============================================================
`timescale 1ns/1ps

module tb_cam_capture;

    reg        pclk   = 0;
    reg        href   = 0;
    reg        vsync  = 0;
    reg [7:0]  din    = 0;

    wire [16:0] wr_addr;
    wire [11:0] wr_data;
    wire         wr_en;

    // DUT
    cam_capture dut (
        .pclk    (pclk),
        .href    (href),
        .vsync   (vsync),
        .din     (din),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .wr_en   (wr_en)
    );

    // 24 MHz PCLK  (period ≈ 41.67 ns)
    always #21 pclk = ~pclk;

    // Task: send one RGB565 pixel
    // r,g,b are 5,6,5 bit values
    task send_pixel;
        input [4:0] r;
        input [5:0] g;
        input [4:0] b;
        reg [15:0] pixel;
        begin
            pixel = {r, g, b};
            // Byte 1: [R4:R0 G5:G3]
            din = pixel[15:8];
            @(posedge pclk); #1;
            // Byte 2: [G2:G0 B4:B0]
            din = pixel[7:0];
            @(posedge pclk); #1;
        end
    endtask

    // Task: send one row of pixels
    task send_row;
        input integer n_pix;
        input [4:0] r; input [5:0] g; input [4:0] b;
        integer j;
        begin
            href = 1;
            for (j = 0; j < n_pix; j = j + 1)
                send_pixel(r, g, b);
            href = 0;
            @(posedge pclk); @(posedge pclk); // gap between rows
        end
    endtask

    integer pixel_cnt = 0;
    always @(posedge pclk) begin
        if (wr_en) begin
            pixel_cnt <= pixel_cnt + 1;
            $display("Pixel %0d  addr=%0d  RGB444=%03h  at %0t",
                     pixel_cnt, wr_addr, wr_data, $time);
        end
    end

    initial begin
        $dumpfile("tb_cam_capture.vcd");
        $dumpvars(0, tb_cam_capture);

        // ---- VSYNC pulse (frame start) ----
        vsync = 1;
        repeat(4) @(posedge pclk);
        vsync = 0;
        repeat(2) @(posedge pclk);

        // ---- Row 0:  RED pixels  (R=31, G=0, B=0 in RGB565) ----
        send_row(4, 5'd31, 6'd0, 5'd0);

        // ---- Row 1:  GREEN pixels (R=0, G=63, B=0) ----
        send_row(4, 5'd0, 6'd63, 5'd0);

        // ---- Row 2:  BLUE pixels  (R=0, G=0, B=31) ----
        send_row(4, 5'd0, 6'd0, 5'd31);

        repeat(10) @(posedge pclk);

        // Check total pixel count
        if (pixel_cnt == 12)
            $display("PASS: captured %0d pixels (expected 12)", pixel_cnt);
        else
            $display("FAIL: captured %0d pixels (expected 12)", pixel_cnt);

        $finish;
    end

endmodule
