// ============================================================
// cam_capture.v  -  OV7670 parallel data capture
//
// The OV7670 in RGB565 mode sends each pixel as TWO bytes:
//   Byte 1 (first PCLK):  [R4:R0 G5:G3]  - upper byte
//   Byte 2 (second PCLK): [G2:G0 B4:B0]  - lower byte
//
// We down-convert to 12-bit RGB444 for BRAM storage:
//   R[3:0] = byte1[7:4]
//   G[3:0] = {byte1[2:0], byte2[7]}  → take top 4 of 6 green bits
//   B[3:0] = byte2[4:1]
//
// Frame size written: 320 x 240 = 76,800 pixels
// ============================================================
module cam_capture (
    input  wire        pclk,
    input  wire        href,
    input  wire        vsync,
    input  wire [7:0]  din,

    output reg  [16:0] wr_addr,
    output reg  [11:0] wr_data,
    output reg         wr_en
);

    reg        byte_sel = 0;     // 0=first byte, 1=second byte
    reg [7:0]  byte1    = 0;
    reg [9:0]  col      = 0;     // 0..
    reg [7:0]  row      = 0;     // 0..239
    reg        vsync_prev = 0;

    always @(posedge pclk) begin
        wr_en      <= 0;
        vsync_prev <= vsync;

        // Rising edge of VSYNC → reset frame position
        if (vsync && !vsync_prev) begin
            col      <= 0;
            row      <= 0;
            byte_sel <= 0;
        end

        if (href) begin
            if (!byte_sel) begin
                // First byte of pixel
                byte1    <= din;
                byte_sel <= 1;
            end else begin
                // Second byte of pixel → assemble RGB444 and write
                byte_sel <= 0;

                // Only store pixels within 320x240 window
                if (col < 320 && row < 240) begin
                    wr_data <= { byte1[7:4],          // R[3:0]
                                 byte1[2:0], din[7],  // G[3:0]
                                 din[4:1]             // B[3:0]
                               };
                    wr_addr <= row * 320 + col;
                    wr_en   <= 1;
                end

                // Advance column
                
                   col <= col + 1;
                
            end
        end else begin
            // HREF just went low → end of line
            if (byte_sel) byte_sel <= 0;  // reset byte alignment
            if (col != 0 || byte_sel) begin
                // Only count row when we actually had pixels
                if (col > 0) begin
                    row <= (row < 239) ? row + 1 : row;
                end
                col <= 0;
            end
        end
    end

endmodule