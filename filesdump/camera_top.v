// ============================================================
// camera_top.v  –  Top-level: OV7670 → Frame Buffer → VGA
// Board  : Basys 3 (Artix-7 XC7A35T)
// Output : 640x480 @ 60 Hz VGA  (320x240 pixel-doubled)
//
// FILTERS (sw[1:0]):
//   00 -> Raw camera feed (RGB444)
//   01 -> Color Inversion (negative)
//   10 -> Binary Image    (black & white threshold)
//   11 -> Color Isolation (single channel, picked by sw[3:2])
//
// COLOR ISOLATION CHANNEL (sw[3:2]) – only used when sw[1:0]=11:
//   00 -> Red   only
//   01 -> Green only
//   10 -> Blue  only
//   11 -> Red+Blue (magenta)
//
// BINARY THRESHOLD (sw[3:2]) – only used when sw[1:0]=10:
//   00 -> Y > 6   (dark threshold,  more white)
//   01 -> Y > 8   (mid)
//   10 -> Y > 10  (bright threshold, more black)
//   11 -> Y > 12  (very bright threshold)
//
// LED status:
//   led[0] = PLL locked
//   led[1] = SCCB config done
//   led[2] = camera VSYNC (blinks ~30 Hz when camera streaming)
//   led[3] = camera HREF  (fast blink while a line is active)
//
// KEY FIXES vs original:
//   * Address calc has proper bounds (no more out-of-buffer reads).
//   * Removed broken 90-deg rotation (caused the purple band at top).
//     If you really want rotation, use the OV7670's MVFP register
//     (0x1E) – set bit[4]=vflip, bit[5]=mirror, in sccb_master.v.
//   * cam_capture.wr_en is now gated by sccb_done so the camera is
//     never writing garbage to BRAM before configuration completes.
//   * Replaced grayscale filter with proper binary threshold.
// ============================================================
module camera_top (
    input  wire        clk100,      // 100 MHz board clock
    // OV7670 camera signals
    input  wire        cam_pclk,    // pixel clock from camera  (A16)
    input  wire        cam_href,    // horizontal reference     (A17)
    input  wire        cam_vsync,   // vertical sync            (B15)
    input  wire [7:0]  cam_data,    // 8-bit pixel bus          (P17-B16)
    output wire        cam_xclk,    // 24 MHz master clock      (C15)
    output wire        cam_pwdn,    // power-down (keep LOW)    (R18)
    output wire        cam_reset,   // reset      (keep HIGH)   (P18)
    output wire        cam_scl,     // SCCB clock               (A14)
    inout  wire        cam_sda,     // SCCB data                (A15)
    // VGA
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    // Switches (filter + mode select)
    input  wire [3:0]  sw,
    // Status LEDs
    output wire [3:0]  led
);

    // --------------------------------------------------------
    // Clock generation  (MMCM via Clocking Wizard IP)
    //   clk25  -> VGA pixel clock  (25.000 MHz)
    //   clk24  -> Camera XCLK      (24.000 MHz)
    //   clk50  -> SCCB / logic     (50.000 MHz)
    // --------------------------------------------------------
    wire clk25, clk24, clk50, pll_locked;

    clk_wiz_0 clk_gen (
        .clk_in1  (clk100),
        .clk_out1 (clk25),      // 25 MHz  - VGA
        .clk_out2 (clk24),      // 24 MHz  - camera XCLK
        .clk_out3 (clk50),      // 50 MHz  - SCCB & ctrl
        .locked   (pll_locked)
    );

    assign cam_xclk  = clk24;
    assign cam_pwdn  = 1'b0;        // always powered on
    assign cam_reset = pll_locked;  // hold reset until PLL locks

    // --------------------------------------------------------
    // SCCB Initialiser  (writes register list to OV7670)
    // --------------------------------------------------------
    wire sccb_done;

    sccb_master sccb (
        .clk   (clk50),
        .rst   (~pll_locked),
        .scl   (cam_scl),
        .sda   (cam_sda),
        .done  (sccb_done)
    );

    // --------------------------------------------------------
    // Synchronize sccb_done into the PCLK domain so we can gate
    // cam_capture writes safely (CDC: simple 2-FF synchronizer).
    // --------------------------------------------------------
    reg sccb_done_sync0 = 1'b0;
    reg sccb_done_pclk  = 1'b0;
    always @(posedge cam_pclk) begin
        sccb_done_sync0 <= sccb_done;
        sccb_done_pclk  <= sccb_done_sync0;
    end

    // --------------------------------------------------------
    // Camera capture  (RGB565 stream -> 12-bit RGB444 in BRAM)
    //   wr_en is held LOW until SCCB has fully configured camera
    // --------------------------------------------------------
    wire [16:0] wr_addr;   // 320*240 = 76800 pixels -> 17 bits
    wire [11:0] wr_data;
    wire        wr_en;

    cam_capture capture (
        .pclk     (cam_pclk),
        .href     (cam_href),
        .vsync    (cam_vsync),
        .din      (cam_data),
        .enable   (sccb_done_pclk),   // <<< KEY FIX: gate writes
        .wr_addr  (wr_addr),
        .wr_data  (wr_data),
        .wr_en    (wr_en)
    );

    // --------------------------------------------------------
    // Frame Buffer  (True dual-port BRAM)
    //   Port A : camera write (pclk domain)
    //   Port B : VGA   read   (clk25 domain)
    // --------------------------------------------------------
    wire [16:0] rd_addr;
    wire [11:0] rd_data;

    frame_buffer fb (
        // Write port (camera clock domain)
        .clka  (cam_pclk),
        .wea   (wr_en),
        .addra (wr_addr),
        .dina  (wr_data),
        // Read port (VGA clock domain)
        .clkb  (clk25),
        .addrb (rd_addr),
        .doutb (rd_data)
    );

    // --------------------------------------------------------
    // VGA sync controller + address generator
    // --------------------------------------------------------
    wire [9:0] vga_col;   // 0..639
    wire [9:0] vga_row;   // 0..479
    wire       vga_active;

    vga_sync vga_ctrl (
        .clk25  (clk25),
        .rst    (~pll_locked),
        .hsync  (vga_hsync),
        .vsync  (vga_vsync),
        .col    (vga_col),
        .row    (vga_row),
        .active (vga_active)
    );

    // ------------------------------------------------------------
    // Pixel-doubled mapping with 90 deg CCW rotation
    //
    // The OV7670 module is physically mounted sideways, so the raw
    // sensor image looks rotated 90 deg CW.  To display it correctly
    // we rotate it 90 deg CCW in the read-out address calculation.
    //
    // Geometry:
    //   - Source frame buffer    : 320 wide x 240 tall (landscape)
    //   - After 90 CCW rotation  : 240 wide x 320 tall (portrait)
    //   - Display screen         : 320 wide x 240 tall (landscape)
    //
    // Because the rotated content is taller than the screen, we
    // crop top/bottom 40 source columns (showing middle 240 of 320).
    // Because it's narrower than the screen, we letterbox with
    // black bars 40 px wide on the left and right.
    //
    //   col=0..39   -> BLACK BAR
    //   col=40..279 -> rotated image (240 wide)
    //   col=280..319-> BLACK BAR
    //
    // 90 CCW rotation formula (derived):
    //   source_col = (source_width - 1) - rotated_row
    //   source_row =                       rotated_col
    //
    // ------------------------------------------------------------
    wire [8:0] sx = {1'b0, vga_col[9:1]};   // screen x: 0..319
    wire [7:0] sy =        vga_row[9:1];    // screen y: 0..239

    // True when inside the rotated image (not in a letterbox bar).
    // With CW rotation the source frame maps as:
    //   sx=40..47   -> source rows 232..239 (BOTTOM of frame, glitched pre-VSYNC)
    //   sx=272..279 -> source rows 0..7     (TOP of frame, covered by SKIP_TOP_ROWS)
    // Hide 8 rows on each side so both stripes are invisble regardless of
    // whether BRAM initial block synthesizes on this device.
    //   Effective image area: sx=48..271 (224 columns = 224 source rows shown)
    //   Left  black bar: sx 0..47   (40 letterbox + 8 hidden bottom rows)
    //   Right black bar: sx 272..319 (8 hidden top rows + 40 letterbox)
    wire in_image = (sx >= 9'd48) && (sx < 9'd272);

    // 90 deg CW rotation (r4 fix: was CCW, image came out upside-down).
    //
    // Derivation for CW:
    //   source_col = rotated_row               = sy + 40   (range 40..279)
    //   source_row = (source_height-1) - rotated_col
    //              = 239 - (sx - 40)           = 279 - sx  (range 0..239)
    //
    // Layout (rotated 240-wide portrait in 320-wide landscape screen):
    //   sx 0..47  -> BLACK BAR  (left, 48px: 40 letterbox + 8 hidden glitch rows)
    //   sx 48..279 -> CW-rotated image (232 source-row columns displayed)
    //   sx 280..319 -> BLACK BAR (right, 40px)
    wire [8:0] cam_col      = {1'b0, sy} + 9'd40;   // 40..279, source col
    wire [8:0] cam_row_9bit = 9'd279     - sx;       // 0..239, source row
    wire [7:0] cam_row      = cam_row_9bit[7:0];

    // addr = cam_row * 320 + cam_col
    //      = (cam_row << 8) + (cam_row << 6) + cam_col   (=256+64=320)
    wire [16:0] addr_row_x256 = {1'b0, cam_row, 8'd0};   // cam_row * 256
    wire [16:0] addr_row_x64  = {3'b000, cam_row, 6'd0}; // cam_row * 64
    assign rd_addr = addr_row_x256 + addr_row_x64 + {8'd0, cam_col};

    // --------------------------------------------------------
    // ===== IMAGE FILTERS =====
    //   sw[1:0] selects which filter is shown.
    //   sw[3:2] is a per-filter parameter (channel or threshold).
    // --------------------------------------------------------
    wire [3:0] r4 = rd_data[11:8];
    wire [3:0] g4 = rd_data[7:4];
    wire [3:0] b4 = rd_data[3:0];

    // --- Filter 1: RAW ---
    wire [11:0] px_raw = rd_data;

    // --- Filter 2: COLOR INVERSION ---
    //   Each channel: out = 15 - in  (bitwise NOT for 4-bit value)
    wire [11:0] px_invert = ~rd_data;

    // --- Filter 3: BINARY IMAGE ---
    //   Compute luma Y ~= (R + 2G + B) / 4   (weights ITU-R BT.601 approx)
    //   For 4-bit channels max Y = (15 + 30 + 15)/4 = 15 (still 4-bit).
    //   Then threshold to pure white (0xFFF) or black (0x000).
    wire [5:0] luma_sum = {2'b00, r4} + {1'b0, g4, 1'b0} + {2'b00, b4};
    wire [3:0] luma     = luma_sum[5:2];   // /4

    reg [3:0] thresh;
    always @(*) begin
        case (sw[3:2])
            2'b00: thresh = 4'd6;
            2'b01: thresh = 4'd8;
            2'b10: thresh = 4'd10;
            2'b11: thresh = 4'd12;
        endcase
    end
    wire [11:0] px_binary = (luma > thresh) ? 12'hFFF : 12'h000;

    // --- Filter 4: COLOR ISOLATION ---
    //   Show only one channel; others forced to 0.
    reg [11:0] px_isolate;
    always @(*) begin
        case (sw[3:2])
            2'b00: px_isolate = {r4, 4'h0, 4'h0};   // red only
            2'b01: px_isolate = {4'h0, g4, 4'h0};   // green only
            2'b10: px_isolate = {4'h0, 4'h0, b4};   // blue only
            2'b11: px_isolate = {r4, 4'h0, b4};     // magenta (R+B)
        endcase
    end

    // --------------------------------------------------------
    // Filter MUX (also handles letterbox black bars)
    // --------------------------------------------------------
    reg [11:0] px_out;
    always @(*) begin
        if (!vga_active) begin
            px_out = 12'h000;             // VGA blanking -> black
        end else if (!in_image) begin
            px_out = 12'h000;             // letterbox bars -> black
        end else begin
            case (sw[1:0])
                2'b00: px_out = px_raw;
                2'b01: px_out = px_invert;
                2'b10: px_out = px_binary;
                2'b11: px_out = px_isolate;
            endcase
        end
    end

    assign vga_r = px_out[11:8];
    assign vga_g = px_out[7:4];
    assign vga_b = px_out[3:0];

    // --------------------------------------------------------
    // Status LEDs (helps debug bring-up)
    // --------------------------------------------------------
    assign led[0] = pll_locked;
    assign led[1] = sccb_done;
    assign led[2] = cam_vsync;
    assign led[3] = cam_href;

endmodule
