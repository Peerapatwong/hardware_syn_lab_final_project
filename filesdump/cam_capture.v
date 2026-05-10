// ============================================================
// cam_capture.v  –  OV7670 parallel data capture
//
// The OV7670 in RGB565 mode sends each pixel as TWO bytes:
//   Byte 1 (first PCLK):  [R4:R0 G5:G3]  – upper byte
//   Byte 2 (second PCLK): [G2:G0 B4:B0]  – lower byte
//
// We down-convert to 12-bit RGB444 for BRAM storage:
//   R[3:0] = byte1[7:4]
//   G[3:0] = {byte1[2:0], byte2[7]}  → top 4 of 6 green bits
//   B[3:0] = byte2[4:1]
//   
//   Byte 1:  S S S S _ S S S
//   Byte 2:  S _ _ S S S S _
//
// Frame size written: 320 x 240 = 76,800 pixels
//
// Key fixes vs. original:
//   1. VSYNC is level-sensitive (not edge-detected) — counters are
//      held reset for the entire blanking interval, preventing any
//      stale writes if HREF spuriously pulses during VSYNC.
//   2. x/y counters replace the fragile col/row logic.  y increments
//      cleanly when x wraps at end-of-line; no dependency on HREF
//      falling edge or col being non-zero.
//   3. wr_addr is a combinational assign from x/y so the address is
//      always valid one cycle before wr_en, matching BRAM setup time.
// ============================================================
module cam_capture (
    input  wire        pclk,
    input  wire        href,
    input  wire        vsync,
    input  wire [7:0]  din,

    output wire [16:0] wr_addr,   // combinational: y*320 + x (2D -> 1D)
    output reg  [11:0] wr_data,
    output reg         wr_en
);

    reg [8:0]  x        = 0;   // 0..319
    reg [7:0]  y        = 0;   // 0..239
    reg        byte_sel = 0;   // 0 = waiting for first byte, 1 = waiting for second
    reg [7:0]  byte1    = 0;   // latched first byte of the RGB565 pair

    // Address is always x + y*320, computed combinationally.
    // Shift+add avoids a multiplier: 320 = 256 + 64
    assign wr_addr = ({1'b0, y, 8'b0} + {3'b0, y, 6'b0}) + {8'b0, x};

    always @(posedge pclk) begin

        // VSYNC high = vertical blanking; hold everything reset.
        // Level-sensitive so the reset persists for the full blanking interval.
        if (vsync) begin
            x        <= 0;
            y        <= 0;
            byte_sel <= 0;
            wr_en    <= 0;

        end else begin
            wr_en <= 0;   // default: no write this cycle

            if (href) begin
                if (!byte_sel) begin
                    // First byte: latch and wait for second
                    byte1    <= din;
                    byte_sel <= 1;
                end else begin
                    // Second byte: assemble RGB444, write, advance position
                    byte_sel <= 0;

                    if (x < 320 && y < 240) begin
                        wr_data <= { byte1[7:4],           // R[3:0]
                                     byte1[2:0], din[7],   // G[3:0]
                                     din[4:1]              // B[3:0]
                                   };
                        wr_en <= 1;
                    end

                    // Advance x; wrap to next row at end of line
                    if (x < 319) begin
                        x <= x + 1;
                    end else begin
                        x <= 0;
                        if (y < 239)
                            y <= y + 1;
                        // else hold at 239 — VSYNC will reset before next frame
                    end
                end

            end else begin
                // HREF low: end of line (or blanking gap between lines).
                // Reset byte alignment so the next HREF rising edge always
                // starts on a clean first-byte boundary.
                byte_sel <= 0;
            end
        end
    end

endmodule