// ============================================================
// vga_sync.v  -  640x480 @ 60 Hz VGA timing generator
//
// Standard 640x480 timing (25.175 MHz pixel clock, use 25 MHz):
//   Horizontal (per line):
//     Visible:     640 pixels
//     Front porch:  16 pixels
//     Sync pulse:   96 pixels  (active LOW)
//     Back porch:   48 pixels
//     Total:       800 pixels
//
//   Vertical (per frame):
//     Visible:     480 lines
//     Front porch:  10 lines
//     Sync pulse:    2 lines   (active LOW)
//     Back porch:   33 lines
//     Total:       525 lines
// ============================================================
module vga_sync (
    input  wire        clk25,
    input  wire        rst,
    output reg         hsync,
    output reg         vsync,
    output reg  [9:0]  col,      // active pixel X (0-639)
    output reg  [9:0]  row,      // active pixel Y (0-479)
    output reg         active    // high only in visible area
);

    // Horizontal counters
    localparam H_VISIBLE    = 640;
    localparam H_FRONT      = 16;
    localparam H_SYNC       = 96;
    localparam H_BACK       = 48;
    localparam H_TOTAL      = 800;  // 640+16+96+48

    // Vertical counters
    localparam V_VISIBLE    = 480;
    localparam V_FRONT      = 10;
    localparam V_SYNC       = 2;
    localparam V_BACK       = 33;
    localparam V_TOTAL      = 525;  // 480+10+2+33

    reg [9:0] h_cnt = 0;
    reg [9:0] v_cnt = 0;

    always @(posedge clk25) begin
        if (rst) begin
            h_cnt  <= 0;
            v_cnt  <= 0;
            hsync  <= 1;
            vsync  <= 1;
            active <= 0;
            col    <= 0;
            row    <= 0;
        end else begin
            // Horizontal counter
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 0;
                else
                    v_cnt <= v_cnt + 1;
            end else begin
                h_cnt <= h_cnt + 1;
            end

            // HSYNC: active LOW during sync pulse
            hsync <= ~((h_cnt >= H_VISIBLE + H_FRONT) &&
                       (h_cnt <  H_VISIBLE + H_FRONT + H_SYNC));

            // VSYNC: active LOW during sync pulse
            vsync <= ~((v_cnt >= V_VISIBLE + V_FRONT) &&
                       (v_cnt <  V_VISIBLE + V_FRONT + V_SYNC));

            // Active video region
            active <= (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

            // Pixel coordinates (only valid when active=1)
            col <= h_cnt;
            row <= v_cnt;
        end
    end

endmodule