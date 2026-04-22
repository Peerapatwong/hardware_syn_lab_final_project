// ============================================================
// frame_buffer.v  –  True Dual-Port BRAM frame buffer
//
// Stores 320x240 pixels at 12 bits each = 921,600 bits ≈ 900 Kbits
// Basys 3 has 1,800 Kbits total BRAM so this fits with room to spare.
//
// Port A : Write (camera clock domain, pclk ~24MHz)
// Port B : Read  (VGA clock domain,    clk25)
//
// Xilinx BRAM primitive inference – Vivado will infer RAMB36E1
// ============================================================
module frame_buffer (
    // Write port (camera)
    input  wire        clka,
    input  wire        wea,
    input  wire [16:0] addra,   // 0..76799  (320*240-1)
    input  wire [11:0] dina,

    // Read port (VGA)
    input  wire        clkb,
    input  wire [16:0] addrb,
    output reg  [11:0] doutb
);

    // 76800 entries × 12 bits
    (* ram_style = "block" *)
    reg [11:0] mem [0:76799];

    // Initialise to mid-grey so you see something before camera starts
    integer i;
    initial begin
        for (i = 0; i < 76800; i = i + 1)
            mem[i] = 12'h888;
    end

    // Port A – synchronous write
    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;
    end

    // Port B – synchronous read (1-cycle latency, fine for VGA pipeline)
    always @(posedge clkb) begin
        doutb <= mem[addrb];
    end

endmodule
