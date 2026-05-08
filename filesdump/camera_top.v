// ============================================================
// camera_top.v — OV7670 → Frame Buffer → VGA with 3 filters
//
// Built from a PROVEN WORKING reference project's SCCB controller
// and 165-register init table, adapted to your Basys 3 pin map.
//
// Filters (selected by sw[1:0]):
//   00 → Raw camera feed
//   01 → Colour Inversion (negative)
//   10 → Binary Image (threshold)
//   11 → Colour Isolation (red channel only)
//
// Clocking:
//   clk_wiz_0 outputs:
//     clk_out1 = 25 MHz → VGA pixel clock, camera XCLK, SCCB
//     clk_out2 = 24 MHz → unused (kept for IP compatibility)
//     clk_out3 = 50 MHz → unused (kept for IP compatibility)
// ============================================================
module camera_top (
    input  wire        clk100,       // 100 MHz board oscillator

    // OV7670 camera
    input  wire        cam_pclk,
    input  wire        cam_href,
    input  wire        cam_vsync,
    input  wire [7:0]  cam_data,
    output wire        cam_xclk,
    output wire        cam_pwdn,
    output wire        cam_reset,
    output wire        cam_scl,
    inout  wire        cam_sda,

    // VGA output
    output wire        vga_hsync,
    output wire        vga_vsync,
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,

    // Switches (filter select)
    input  wire [1:0]  sw,

    // Status LEDs
    output wire [3:0]  led
);

    // ============================================================
    // Clocks
    // ============================================================
    wire clk25, clk24, clk50, pll_locked;

    clk_wiz_0 clk_gen (
        .clk_in1  (clk100),
        .clk_out1 (clk25),      // 25 MHz — used for everything
        .clk_out2 (clk24),      // 24 MHz — not used
        .clk_out3 (clk50),      // 50 MHz — not used
        .locked   (pll_locked)
    );

    // XCLK = 25 MHz (matches the working reference project)
    assign cam_xclk = clk25;
    assign cam_pwdn = 1'b0;     // always powered on
    assign cam_reset = 1'b1;    // not in reset (active-low)

    // ============================================================
    // SCCB Camera Configuration (proven working controller)
    // ============================================================
    wire config_done;

    I2C_AV_Config sccb_config (
        .iCLK       (clk25),
        .iRST_N     (pll_locked),  // hold in reset until PLL locks
        .I2C_SCLK   (cam_scl),
        .I2C_SDAT   (cam_sda),
        .Config_Done(config_done),
        .LUT_INDEX  (),
        .I2C_RDATA  ()
    );

    // ============================================================
    // Camera Pixel Capture (proven working module)
    // ============================================================
    wire [16:0] wr_addr;
    wire [11:0] wr_data;
    wire        wr_en;

    ov7670_capture capture (
        .pclk  (cam_pclk),
        .vsync (cam_vsync),
        .href  (cam_href),
        .d     (cam_data),
        .addr  (wr_addr),
        .dout  (wr_data),
        .we    (wr_en)
    );

    // ============================================================
    // Frame Buffer (your existing module — keep frame_buffer.v)
    // ============================================================
    wire [16:0] rd_addr;
    wire [11:0] rd_data;

    frame_buffer fb (
        .clka  (cam_pclk),
        .wea   (wr_en),
        .addra (wr_addr),
        .dina  (wr_data),
        .clkb  (clk25),
        .addrb (rd_addr),
        .doutb (rd_data)
    );

    // ============================================================
    // VGA Timing Generator (640×480 @ 60 Hz, 25 MHz pixel clock)
    // ============================================================
    parameter H_VISIBLE  = 640;
    parameter H_FRONT    = 16;
    parameter H_SYNC     = 96;
    parameter H_BACK     = 48;
    parameter H_TOTAL    = 800;

    parameter V_VISIBLE  = 480;
    parameter V_FRONT    = 10;
    parameter V_SYNC     = 2;
    parameter V_BACK     = 33;
    parameter V_TOTAL    = 525;

    reg [9:0] h_cnt = 0;
    reg [9:0] v_cnt = 0;
    reg       blank = 1;

    always @(posedge clk25) begin
        if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 0;
            else
                v_cnt <= v_cnt + 1;
        end else begin
            h_cnt <= h_cnt + 1;
        end

        // Blanking flag
        blank <= (h_cnt >= H_VISIBLE) || (v_cnt >= V_VISIBLE);
    end

    assign vga_hsync = ~((h_cnt >= H_VISIBLE + H_FRONT) &&
                         (h_cnt <  H_VISIBLE + H_FRONT + H_SYNC));
    assign vga_vsync = ~((v_cnt >= V_VISIBLE + V_FRONT) &&
                         (v_cnt <  V_VISIBLE + V_FRONT + V_SYNC));

    // ============================================================
    // Pixel-double address mapping: VGA 640×480 → BRAM 320×240
    // ============================================================
    wire [8:0] cam_x = h_cnt[9:1];   // 0..319  (÷2 horizontal)
    wire [7:0] cam_y = v_cnt[8:1];   // 0..239  (÷2 vertical)

    // Simple straight mapping (no rotation):
    assign rd_addr = cam_y * 17'd320 + {8'd0, cam_x};

    // If image appears rotated 90°, try one of these instead:
    //   assign rd_addr = cam_x * 17'd320 + (17'd319 - {9'd0, cam_y});
    //   assign rd_addr = (17'd239 - {9'd0, cam_y}) * 17'd320 + {8'd0, cam_x};

    // ============================================================
    // Image Filters
    //   sw = 00 → Raw
    //   sw = 01 → Colour Inversion (negative)
    //   sw = 10 → Binary Image (threshold)
    //   sw = 11 → Colour Isolation (red channel only)
    // ============================================================
    wire [3:0] raw_r = rd_data[11:8];
    wire [3:0] raw_g = rd_data[ 7:4];
    wire [3:0] raw_b = rd_data[ 3:0];

    // Grayscale intensity for thresholding: (R + G + B) / 4
    wire [5:0] gray_sum = {2'b00, raw_r} + {2'b00, raw_g} + {2'b00, raw_b};
    wire [3:0] gray     = gray_sum[5:2];

    // Binary threshold: above mid-point → white, below → black
    wire [3:0] binary   = (gray > 4'd5) ? 4'hF : 4'h0;

    always @(posedge clk25) begin
        if (blank) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            case (sw)
                2'b00: begin  // Raw
                    vga_r <= raw_r;
                    vga_g <= raw_g;
                    vga_b <= raw_b;
                end
                2'b01: begin  // Colour Inversion (negative)
                    vga_r <= ~raw_r;
                    vga_g <= ~raw_g;
                    vga_b <= ~raw_b;
                end
                2'b10: begin  // Binary Image (threshold)
                    vga_r <= binary;
                    vga_g <= binary;
                    vga_b <= binary;
                end
                2'b11: begin  // Colour Isolation (red only)
                    vga_r <= raw_r;
                    vga_g <= 4'h0;
                    vga_b <= 4'h0;
                end
            endcase
        end
    end

    // ============================================================
    // Status LEDs
    // ============================================================
    assign led[0] = pll_locked;
    assign led[1] = config_done;
    assign led[2] = cam_vsync;
    assign led[3] = cam_href;

endmodule
