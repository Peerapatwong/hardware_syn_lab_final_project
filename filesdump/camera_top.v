// ============================================================
// camera_top.v  –  Top-level: OV7670 → Frame Buffer → VGA
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
        .clk_out1 (clk25),      // 25 MHz  – VGA
        .clk_out2 (clk24),      // 24 MHz  – camera XCLK
        .clk_out3 (clk50),      // 50 MHz  – SCCB & ctrl
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
    // Frame Buffer  (BRAM – true dual port)
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

    // Pixel-double: map 640x480 display → 320x240 frame buffer
    assign rd_addr = ({1'b0, vga_row[9:1]} * 320) + {1'b0, vga_col[9:1]};
    // Note: multiply by 320 can be done as shift+add:
    // row/2 * 256 + row/2 * 64 = (row/2)<<8 + (row/2)<<6

    // --------------------------------------------------------
    // Image Filters  (sw[1:0] selects output)
    //   00 → raw
    //   01 → grayscale
    //   10 → negative
    //   11 → red-channel only
    // --------------------------------------------------------
    wire [11:0] px_raw    = rd_data;

    // Grayscale: average R+G+B (all 4-bit channels)
    wire [5:0]  gray_sum  = {2'b00,rd_data[11:8]} +
                            {2'b00,rd_data[7:4]}  +
                            {2'b00,rd_data[3:0]};
    wire [3:0]  gray4     = gray_sum[5:2];         // divide by ~4 (close enough)
    wire [11:0] px_gray   = {gray4, gray4, gray4};

    wire [11:0] px_neg    = ~rd_data;              // invert all channels

    wire [11:0] px_red    = {rd_data[11:8], 4'h0, 4'h0};  // R only

    reg  [11:0] px_out;
    always @(*) begin
        if (!vga_active) begin
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

    // Status LEDs
    assign led[0] = pll_locked;
    assign led[1] = sccb_done;
    assign led[2] = cam_vsync;
    assign led[3] = cam_href;

endmodule
