// ============================================================
// cam_capture.v  –  OV7670 parallel data capture
//
// The OV7670 in RGB565 mode sends each pixel as TWO bytes:
//   Byte 1 (first PCLK):  [R4 R3 R2 R1 R0 G5 G4 G3]
//   Byte 2 (second PCLK): [G2 G1 G0 B4 B3 B2 B1 B0]
//
// We down-convert to 12-bit RGB444 for BRAM storage:
//   R[3:0] = byte1[7:4]              (top 4 of 5 red bits)
//   G[3:0] = {byte1[2:0], byte2[7]}  (top 4 of 6 green bits)
//   B[3:0] = byte2[4:1]              (top 4 of 5 blue bits)
//
// Frame size written: 320 x 240 = 76,800 pixels
//
// Key features:
//   1. VSYNC is LEVEL-SENSITIVE.  While VSYNC is high we hold every
//      counter in reset so a glitchy HREF during blanking can never
//      poison the buffer.
//   2. wr_addr is COMBINATIONAL (= y*320 + x) so it is valid one
//      cycle before wr_en – correct setup time for the BRAM.
//   3. 'enable' input gates wr_en.  Tie this to sccb_done so the
//      BRAM is never written before camera registers are programmed
//      (the camera defaults to VGA otherwise – writes garbage).
//   4. The first SKIP_TOP_ROWS lines of each frame are skipped (still
//      counted but no write).  This hides the residual blanking
//      stripe the OV7670 emits and which was visible as a magenta
//      band at the top of the screen.
// ============================================================
module cam_capture #(
    // How many rows at top of each frame to discard.  These contain
    // the OV7670's residual blanking/colour-balance pixels which
    // appeared as a magenta band on screen.  Override to 0 in
    // testbenches that send only a few pixels per row.
    parameter [7:0] SKIP_TOP_ROWS = 8'd8     // r3-fix: was 2, bumped to 8
                                              // because OV7670 emits glitched
                                              // pixels for the first few rows
                                              // of every frame and they now
                                              // show up at the LEFT edge of
                                              // the rotated image.
) (
    input  wire        pclk,
    input  wire        href,
    input  wire        vsync,
    input  wire [7:0]  din,
    input  wire        enable,    // tie HIGH to allow BRAM writes (use sccb_done)

    output wire [16:0] wr_addr,   // combinational: y*320 + x
    output reg  [11:0] wr_data,
    output reg         wr_en
);

    // ----- pixel position counters --------------------------------
    reg [8:0]  x        = 0;   // 0..319
    reg [7:0]  y        = 0;   // 0..239
    reg        byte_sel = 0;   // 0 = waiting for first byte, 1 = second
    reg [7:0]  byte1    = 0;   // latched first byte of an RGB565 pair

    // ----- combinational address: y*320 + x = (y<<8)+(y<<6)+x ----
    wire [16:0] y_x256 = {1'b0,  y, 8'd0};   // y * 256
    wire [16:0] y_x64  = {3'b0,  y, 6'd0};   // y *  64
    assign      wr_addr = y_x256 + y_x64 + {8'd0, x};

    // ----- main state ---------------------------------------------
    always @(posedge pclk) begin

        if (vsync) begin
            // Vertical blanking: hold everything in reset.
            x        <= 0;
            y        <= 0;
            byte_sel <= 0;
            wr_en    <= 0;

        end else begin
            wr_en <= 1'b0;          // default: no write this cycle

            if (href) begin
                if (!byte_sel) begin
                    // First byte of pair – latch and wait for byte 2.
                    byte1    <= din;
                    byte_sel <= 1'b1;
                end else begin
                    // Second byte – assemble RGB444 + advance position.
                    byte_sel <= 1'b0;

                    // Only WRITE when:
                    //   (a) camera has been configured (enable=1)
                    //   (b) we are inside the 320x240 region
                    //   (c) we are past the SKIP_TOP_ROWS blanking strip
                    if (enable && x < 320 && y < 240 && y >= SKIP_TOP_ROWS) begin
                        wr_data <= { byte1[7:4],           // R[3:0]
                                     byte1[2:0], din[7],   // G[3:0]
                                     din[4:1]              // B[3:0]
                                   };
                        wr_en <= 1'b1;
                    end

                    // Advance x; wrap to next row at end-of-line.
                    if (x < 319) begin
                        x <= x + 9'd1;
                    end else begin
                        x <= 0;
                        if (y < 239)
                            y <= y + 8'd1;
                        // else hold at 239; VSYNC will reset next frame.
                    end
                end
            end else begin
                // HREF low – inter-line gap.  Reset byte_sel so the next
                // HREF rising edge ALWAYS starts on a clean byte boundary.
                byte_sel <= 1'b0;
            end
        end
    end

endmodule
