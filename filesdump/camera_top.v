// ============================================================
// camera_top.v  -  Top-level: OV7670 → Frame Buffer → VGA
// Board  : Basys 3 (Artix-7 XC7A35T)
// Output : 640x480 @ 60 Hz VGA  (320x240 pixel-doubled)
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
    // Switches (filter select)
    input  wire [1:0]  sw,
    // Status LEDs
    output wire [3:0]  led
);
 
    // --------------------------------------------------------
    // Clock generation  (MMCM via Clocking Wizard IP)
    //   clk25  → VGA pixel clock  (25.175 MHz, use 25 MHz)
    //   clk24  → Camera XCLK      (24 MHz)
    //   clk50  → SCCB / logic     (50 MHz)
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
    assign cam_pwdn  = 1'b0;   // always powered on
    assign cam_reset = pll_locked;  // hold reset until PLL locks
 
    // --------------------------------------------------------
    // SCCB Initialiser  (writes register list to OV7670)
    // --------------------------------------------------------
    wire sccb_done;
 
    sccb_master sccb (
        .clk       (clk50),
        .rst       (~pll_locked),
        .scl       (cam_scl),
        .sda       (cam_sda),
        .done      (sccb_done)
    );
 
    // FIX #1: CDC synchroniser for sccb_done (clk50 → clk25 domain).
    // sccb_done is a static flag once asserted, but crossing clock domains
    // without a synchroniser can cause metastability on the LED output and
    // any downstream logic that might gate on it.
    reg sccb_done_s1, sccb_done_sync;
    always @(posedge clk25) begin
        sccb_done_s1   <= sccb_done;
        sccb_done_sync <= sccb_done_s1;
    end
 
    // --------------------------------------------------------
    // Camera capture  (RGB565 → 12-bit RGB444 stored in BRAM)
    // --------------------------------------------------------
    wire [16:0] wr_addr;   // 320*240 = 76800 pixels → 17 bits
    wire [11:0] wr_data;   // RGB 4-4-4
    wire        wr_en;
 
    cam_capture capture (
        .pclk      (cam_pclk),
        .href      (cam_href),
        .vsync     (cam_vsync),
        .din       (cam_data),
        .wr_addr   (wr_addr),
        .wr_data   (wr_data),
        .wr_en     (wr_en)
    );
 
    // --------------------------------------------------------
    // Frame Buffer  (BRAM - true dual port)
    //   Port A : camera write
    //   Port B : VGA read
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
    wire [9:0] vga_col;   // 0-639
    wire [9:0] vga_row;   // 0-479
    wire       vga_active;
 
    vga_sync vga_ctrl (
        .clk25     (clk25),
        .rst       (~pll_locked),
        .hsync     (vga_hsync),
        .vsync     (vga_vsync),
        .col       (vga_col),
        .row       (vga_row),
        .active    (vga_active)
    );
 
    // FIX #2: Explicit bit widths in rd_addr calculation.
    // Without zero-extension the 9-bit slice shifted left by 8 can silently
    // overflow in Verilog's expression width rules, corrupting addresses near
    // the end of each row.  Zero-extend every operand to 17 bits first.
    //
    // row/2 * 320 = (row/2)<<8 + (row/2)<<6  (256 + 64 = 320) ✓
    assign rd_addr = ({8'b0, vga_row[9:1]} << 8)   // row/2 * 256
                   + ({8'b0, vga_row[9:1]} << 6)   // row/2 *  64
                   + {10'b0, vga_col[9:1]};         // col/2
 
    // FIX #3: Pipeline vga_active by one cycle to compensate for the BRAM
    // read latency.  The BRAM registered-output mode adds exactly 1 clk25
    // cycle between presenting rd_addr and seeing valid rd_data.  Without
    // this, the first pixel of every active line and the blanking edge are
    // each off by one pixel, producing a thin coloured stripe on the left
    // edge of the image.
    reg vga_active_d;
    always @(posedge clk25) vga_active_d <= vga_active;
 
    // --------------------------------------------------------
    // Image Filters  (sw[1:0] selects output)
    //   00 → raw
    //   01 → grayscale
    //   10 → negative
    //   11 → red-channel only
    // --------------------------------------------------------
    wire [11:0] px_raw = rd_data;
 
    // FIX #4: Divide by 3, not 4, for a correct grayscale average.
    // gray_sum is at most 3*15 = 45 (fits in 6 bits).
    // Shifting right by 2 (i.e. >>2) divides by 4, making the image ~25%
    // darker than it should be.  A divide-by-3 is cheap at this word width
    // and synthesises to a small LUT chain.
    wire [5:0] gray_sum = {2'b00, rd_data[11:8]}
                        + {2'b00, rd_data[7:4]}
                        + {2'b00, rd_data[3:0]};
    wire [3:0] gray4    = gray_sum / 3;             // true average ÷3
    wire [11:0] px_gray = {gray4, gray4, gray4};
 
    wire [11:0] px_neg  = ~rd_data;                 // invert all channels
 
    wire [11:0] px_red  = {rd_data[11:8], 4'h0, 4'h0}; // R only
 
    // Use the pipelined active signal so blanking lines up with pixel data.
    reg [11:0] px_out;
    always @(*) begin
        if (!vga_active_d) begin                    // FIX #3 applied here
            px_out = 12'h000;
        end else begin
            case (sw)
                2'b00: px_out = px_raw;
                2'b01: px_out = px_gray;
                2'b10: px_out = px_neg;
                2'b11: px_out = px_red;
            endcase
        end
    end
 
    assign vga_r = px_out[11:8];
    assign vga_g = px_out[7:4];
    assign vga_b = px_out[3:0];
 
    // Status LEDs - use synchronised sccb_done_sync (FIX #1)
    assign led[0] = pll_locked;
    assign led[1] = sccb_done_sync;
    assign led[2] = cam_vsync;
    assign led[3] = cam_href;
 
endmodule