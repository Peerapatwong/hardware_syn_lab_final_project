// ============================================================
// cam_capture.v — OV7670 pixel capture (from working reference)
//
// Latches 2 bytes per pixel on PCLK, converts RGB565 → RGB444,
// outputs write address + data + enable for the frame buffer.
// ============================================================
module ov7670_capture (
    input             pclk,
    input             vsync,
    input             href,
    input  [7:0]      d,
    output [16:0]     addr,
    output [11:0]     dout,
    output reg        we
);

    reg [15:0] d_latch = 0;
    reg [11:0] dout1   = 0;
    reg [1:0]  wr_hold = 0;
    reg [9:0]  x       = 0;
    reg [9:0]  y       = 0;

    assign addr = y * 320 + x;
    assign dout = dout1;

    always @(posedge pclk) begin
        if (vsync) begin
            // VSYNC high = vertical blanking → reset for new frame
            x       <= 0;
            y       <= 0;
            wr_hold <= 0;
            we      <= 0;
        end else begin
            // Shift in new byte (first byte → MSB, second → LSB)
            d_latch <= {d_latch[7:0], d};

            // Toggle wr_hold to fire write-enable every 2nd PCLK
            wr_hold <= {wr_hold[0], (href && !wr_hold[0])};

            // Write enable is delayed by one more cycle
            we <= wr_hold[1];

            if (wr_hold[1]) begin
                // RGB565 → RGB444
                dout1 <= {
                    d_latch[15:12],   // R[4:1]
                    d_latch[10:7],    // G[5:2]
                    d_latch[4:1]      // B[4:1]
                };

                // Advance pixel position
                if (x < 319) begin
                    x <= x + 1;
                end else begin
                    x <= 0;
                    if (y < 239)
                        y <= y + 1;
                    else
                        y <= 0;
                end
            end
        end
    end

endmodule
