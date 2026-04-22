// ============================================================
// tb_vga_sync.v  –  Testbench for vga_sync module
// Verifies HSYNC/VSYNC pulses and active region timing
// Run for at least 2 full frames (~16.7ms each @ 25MHz)
// ============================================================
`timescale 1ns/1ps

module tb_vga_sync;

    // DUT signals
    reg        clk25  = 0;
    reg        rst    = 1;
    wire       hsync, vsync, active;
    wire [9:0] col, row;

    // Instantiate DUT
    vga_sync dut (
        .clk25  (clk25),
        .rst    (rst),
        .hsync  (hsync),
        .vsync  (vsync),
        .col    (col),
        .row    (row),
        .active (active)
    );

    // 25 MHz clock  (period = 40 ns)
    always #20 clk25 = ~clk25;

    // Release reset after 5 cycles
    initial begin
        #100 rst = 0;
    end

    // ---- Monitoring counters ----
    integer h_active_cnt = 0;
    integer v_active_cnt = 0;
    integer hsync_pulses = 0;
    integer vsync_pulses = 0;
    reg     hsync_prev = 1;
    reg     vsync_prev = 1;

    always @(posedge clk25) begin
        // Count active pixels per line
        if (active) h_active_cnt <= h_active_cnt + 1;

        // Count HSYNC falling edges
        if (!hsync && hsync_prev) begin
            hsync_pulses <= hsync_pulses + 1;
            $display("HSYNC pulse #%0d at time %0t", hsync_pulses+1, $time);
        end

        // Count VSYNC falling edges
        if (!vsync && vsync_prev) begin
            vsync_pulses <= vsync_pulses + 1;
            $display("VSYNC pulse #%0d at time %0t  (row=%0d)", vsync_pulses+1, $time, row);
        end

        hsync_prev <= hsync;
        vsync_prev <= vsync;
    end

    // ---- Run for 2 complete frames then check ----
    // 1 frame = 525 lines × 800 pixels = 420,000 clocks
    // 2 frames = 840,000 clocks × 40ns = 33.6ms
    initial begin
        $dumpfile("tb_vga_sync.vcd");
        $dumpvars(0, tb_vga_sync);

        #33_600_000; // 33.6ms

        // Assertions
        if (hsync_pulses == 1050)
            $display("PASS: Got %0d HSYNC pulses (expected 1050 for 2 frames)", hsync_pulses);
        else
            $display("FAIL: Got %0d HSYNC pulses (expected 1050)", hsync_pulses);

        if (vsync_pulses == 2)
            $display("PASS: Got %0d VSYNC pulses", vsync_pulses);
        else
            $display("FAIL: Got %0d VSYNC pulses (expected 2)", vsync_pulses);

        $finish;
    end

endmodule
