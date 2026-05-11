// ============================================================
// sccb_master.v  -  SCCB (I2C-like) master for OV7670 config
// Writes a fixed register table then asserts done.
// Clock: 50 MHz input → ~100 kHz SCCB clock
//
// Register table: 4 reset/init entries + 165 full config entries
// from the completed reference set = 169 total.
// ============================================================
module sccb_master (
    input  wire clk,       // 50 MHz
    input  wire rst,
    output reg  scl,
    inout  wire sda,
    output reg  done
);

    // OV7670 write address
    localparam CAM_ADDR = 8'h42;

    // SCCB divider: 50MHz / 500 = 100kHz, 4 phases → 125 cycles each
    localparam DIV = 125;

    // --------------------------------------------------------
    // Configurations for SCCB (RGB mode, resolution, noise cancellation, etc.)
    // Register init table  [reg_addr, value]
    // 169 entries total:
    //   [0..1]   - COM7 soft reset (sent twice for reliability)
    //   [2..3]   - COM7 RGB mode + COM15 RGB565 (applied before full config)
    //   [4..168] - Full 165-entry config from completed reference set
    // --------------------------------------------------------
    localparam N_REGS = 169;

    reg [15:0] reg_table [0:N_REGS-1];
    initial begin
        // -- Reset sequence (always send first) --
        reg_table[0]   = 16'h1280; // COM7  - soft reset
        reg_table[1]   = 16'h1280; // COM7  - soft reset again (safety)
        reg_table[2]   = 16'h1204; // COM7  - select RGB output format
        reg_table[3]   = 16'h40D0; // COM15 - RGB565, full output range

        // -- Full configuration (from completed reference set) --
        // Indices below correspond to SET_OV7670 + 0..164 in the original LUT.
        // SET_OV7670 base offset is 2 in that file; we strip it and embed directly.
        reg_table[4]   = 16'h1214; // COM7  - QVGA, RGB
        reg_table[5]   = 16'h40d0; // COM15 - RGB565, full range (re-affirm)
        reg_table[6]   = 16'h3a04; // TSLB  - YUYV sequence
        reg_table[7]   = 16'h3dc8; // COM13 - gamma enable, UV auto adjust
        reg_table[8]   = 16'h1e31; // MVFP  - mirror + vflip (adjust to suit camera orientation)
        reg_table[9]   = 16'h6b00; // DBLV  - PLL bypass
        reg_table[10]  = 16'h32b6; // HREF  - HREF control
        reg_table[11]  = 16'h1713; // HSTART - horizontal frame start
        reg_table[12]  = 16'h1801; // HSTOP  - horizontal frame stop
        reg_table[13]  = 16'h1902; // VSTART - vertical frame start
        reg_table[14]  = 16'h1a7a; // VSTOP  - vertical frame stop
        reg_table[15]  = 16'h030a; // VREF   - vertical frame control
        reg_table[16]  = 16'h0c00; // COM3   - no scaling, DCW off
        reg_table[17]  = 16'h3e00; // COM14  - no PCLK divider
        reg_table[18]  = 16'h7000; // SCALING_XSC
        reg_table[19]  = 16'h7100; // SCALING_YSC
        reg_table[20]  = 16'h7211; // SCALING_DCWCTR
        reg_table[21]  = 16'h7300; // SCALING_PCLK_DIV
        reg_table[22]  = 16'ha202; // SCALING_PCLK_DELAY
        reg_table[23]  = 16'h1180; // CLKRC  - use external clock directly
        // Gamma curve (0x7a-0x89)
        reg_table[24]  = 16'h7a20; // SLOP
        reg_table[25]  = 16'h7b1c; // GAM1
        reg_table[26]  = 16'h7c28; // GAM2
        reg_table[27]  = 16'h7d3c; // GAM3
        reg_table[28]  = 16'h7e55; // GAM4
        reg_table[29]  = 16'h7f68; // GAM5
        reg_table[30]  = 16'h8076; // GAM6
        reg_table[31]  = 16'h8180; // GAM7
        reg_table[32]  = 16'h8288; // GAM8
        reg_table[33]  = 16'h838f; // GAM9
        reg_table[34]  = 16'h8496; // GAM10
        reg_table[35]  = 16'h85a3; // GAM11
        reg_table[36]  = 16'h86af; // GAM12
        reg_table[37]  = 16'h87c4; // GAM13
        reg_table[38]  = 16'h88d7; // GAM14
        reg_table[39]  = 16'h89e8; // GAM15
        // AGC/AWB control
        reg_table[40]  = 16'h13e0; // COM8  - disable AGC/AWB/AEC (manual mode first)
        reg_table[41]  = 16'h0000; // GAIN
        reg_table[42]  = 16'h1000; // AECH (exposure high bits)
        reg_table[43]  = 16'h0d00; // COM4
        reg_table[44]  = 16'h1428; // COM9   - AGC ceiling x4
        reg_table[45]  = 16'ha505; // BD50MAX
        reg_table[46]  = 16'hab07; // DB60MAX
        reg_table[47]  = 16'h2475; // AEW    - AGC/AEC upper limit
        reg_table[48]  = 16'h2563; // AEB    - AGC/AEC lower limit
        reg_table[49]  = 16'h26a5; // VPT    - AGC/AEC fast mode limits
        reg_table[50]  = 16'h9f78; // HAECC1
        reg_table[51]  = 16'ha068; // HAECC2
        reg_table[52]  = 16'ha103; // HAECC3 (partial)
        reg_table[53]  = 16'ha6df; // HAECC3
        reg_table[54]  = 16'ha7df; // HAECC4
        reg_table[55]  = 16'ha8f0; // HAECC5
        reg_table[56]  = 16'ha990; // HAECC6
        reg_table[57]  = 16'haa94; // HAECC7
        reg_table[58]  = 16'h13ef; // COM8  - re-enable AGC/AWB/AEC
        // Image quality
        reg_table[59]  = 16'h0e61; // COM5
        reg_table[60]  = 16'h0f4b; // COM6
        reg_table[61]  = 16'h1602; // reserved
        reg_table[62]  = 16'h2102; // ADCCTR1 (partial)
        reg_table[63]  = 16'h2291; // ADCCTR2 (partial)
        reg_table[64]  = 16'h2907; // reserved
        reg_table[65]  = 16'h330b; // CHLF
        reg_table[66]  = 16'h350b; // reserved
        reg_table[67]  = 16'h371d; // ADC
        reg_table[68]  = 16'h3871; // ACOM
        reg_table[69]  = 16'h392a; // OFON
        reg_table[70]  = 16'h3c78; // COM12
        reg_table[71]  = 16'h4d40; // reserved
        reg_table[72]  = 16'h4e20; // reserved
        reg_table[73]  = 16'h6900; // GFIX
        reg_table[74]  = 16'h7419; // REG74
        reg_table[75]  = 16'h8d4f; // reserved
        reg_table[76]  = 16'h8e00; // reserved
        reg_table[77]  = 16'h8f00; // reserved
        reg_table[78]  = 16'h9000; // reserved
        reg_table[79]  = 16'h9100; // reserved
        reg_table[80]  = 16'h9200; // reserved
        reg_table[81]  = 16'h9600; // reserved
        reg_table[82]  = 16'h9a80; // reserved
        reg_table[83]  = 16'hb084; // RSVD-B0
        reg_table[84]  = 16'hb10c; // ABLC1
        reg_table[85]  = 16'hb20e; // reserved
        reg_table[86]  = 16'hb382; // THL_ST
        reg_table[87]  = 16'hb80a; // reserved
        // Color matrix (saturation / hue)
        reg_table[88]  = 16'h4314; // MTX1
        reg_table[89]  = 16'h44f0; // MTX2
        reg_table[90]  = 16'h4534; // MTX3
        reg_table[91]  = 16'h4658; // MTX4
        reg_table[92]  = 16'h4728; // MTX5
        reg_table[93]  = 16'h483a; // MTX6
        // Auto de-noise / edge enhancement
        reg_table[94]  = 16'h5988; // DNSTH
        reg_table[95]  = 16'h5a88; // reserved
        reg_table[96]  = 16'h5b44; // reserved
        reg_table[97]  = 16'h5c67; // reserved
        reg_table[98]  = 16'h5d49; // reserved
        reg_table[99]  = 16'h5e0e; // reserved
        reg_table[100] = 16'h6404; // BDBASE
        reg_table[101] = 16'h6520; // DBSTEP
        reg_table[102] = 16'h6605; // DBLV (partial)
        reg_table[103] = 16'h9404; // reserved
        reg_table[104] = 16'h9508; // reserved
        // AWB advanced
        reg_table[105] = 16'h6c0a; // AWBCTR3
        reg_table[106] = 16'h6d55; // AWBCTR2
        reg_table[107] = 16'h6e11; // AWBCTR1
        reg_table[108] = 16'h6f9f; // AWBCTR0
        reg_table[109] = 16'h6a40; // GGAIN
        reg_table[110] = 16'h0140; // BLUE gain
        reg_table[111] = 16'h0240; // RED gain
        reg_table[112] = 16'h13e7; // COM8  - enable all auto functions
        reg_table[113] = 16'h1500; // COM10 - PCLK/VSYNC/HREF polarity
        // Color matrix (full)
        reg_table[114] = 16'h4f80; // MTX1
        reg_table[115] = 16'h5080; // MTX2
        reg_table[116] = 16'h5100; // MTX3
        reg_table[117] = 16'h5222; // MTX4
        reg_table[118] = 16'h535e; // MTX5
        reg_table[119] = 16'h5480; // MTX6
        reg_table[120] = 16'h589e; // MTXS  - matrix coefficient sign + auto contrast
        // Misc
        reg_table[121] = 16'h4108; // COM21 (partial)
        reg_table[122] = 16'h3f00; // EDGE
        reg_table[123] = 16'h7505; // REG75
        reg_table[124] = 16'h76e1; // REG76
        reg_table[125] = 16'h4c00; // DNSTH (partial)
        reg_table[126] = 16'h7701; // REG77
        reg_table[127] = 16'h4b09; // reserved
        reg_table[128] = 16'hc9f0; // reserved
        reg_table[129] = 16'h4138; // COM21
        reg_table[130] = 16'h5640; // reserved
        // Lens correction
        reg_table[131] = 16'h3411; // ARBLM
        reg_table[132] = 16'h3b02; // COM11
        reg_table[133] = 16'ha489; // reserved
        reg_table[134] = 16'h9600; // reserved
        reg_table[135] = 16'h9730; // reserved
        reg_table[136] = 16'h9820; // reserved
        reg_table[137] = 16'h9930; // reserved
        reg_table[138] = 16'h9a84; // reserved
        reg_table[139] = 16'h9b29; // reserved
        reg_table[140] = 16'h9c03; // reserved
        reg_table[141] = 16'h9d4c; // reserved
        reg_table[142] = 16'h9e3f; // reserved
        reg_table[143] = 16'h7804; // reserved
        // Luminance signal processing (register 0x79 / 0xc8 pairs)
        reg_table[144] = 16'h7901; // register index write
        reg_table[145] = 16'hc8f0; // register data write
        reg_table[146] = 16'h790f; // register index write
        reg_table[147] = 16'hc800; // register data write
        reg_table[148] = 16'h7910; // register index write
        reg_table[149] = 16'hc87e; // register data write
        reg_table[150] = 16'h790a; // register index write
        reg_table[151] = 16'hc880; // register data write
        reg_table[152] = 16'h790b; // register index write
        reg_table[153] = 16'hc801; // register data write
        reg_table[154] = 16'h790c; // register index write
        reg_table[155] = 16'hc80f; // register data write
        reg_table[156] = 16'h790d; // register index write
        reg_table[157] = 16'hc820; // register data write
        reg_table[158] = 16'h7909; // register index write
        reg_table[159] = 16'hc880; // register data write
        reg_table[160] = 16'h7902; // register index write
        reg_table[161] = 16'hc8c0; // register data write
        reg_table[162] = 16'h7903; // register index write
        reg_table[163] = 16'hc840; // register data write
        reg_table[164] = 16'h7905; // register index write
        reg_table[165] = 16'hc830; // register data write
        reg_table[166] = 16'h7926; // end of luminance block
        // Final
        reg_table[167] = 16'h0903; // COM6  - reset timing
        reg_table[168] = 16'h3b42; // COM11 - night mode / banding filter
    end

    // --------------------------------------------------------
    // State machine
    // --------------------------------------------------------
    localparam S_IDLE      = 0,
               S_START     = 1,
               S_ADDR      = 2,
               S_ACK1      = 3,
               S_REG       = 4,
               S_ACK2      = 5,
               S_DATA      = 6,
               S_ACK3      = 7,
               S_STOP      = 8,
               S_PAUSE     = 9,
               S_DONE      = 10;

    reg [3:0]  state   = S_IDLE;
    reg [7:0]  div_cnt = 0;
    reg [1:0]  phase   = 0;      // 0=SCL_LOW, 1=SCL_RISE, 2=SCL_HIGH, 3=SCL_FALL
    reg [7:0]  reg_idx = 0;      // widened to 8-bit to index up to 255 entries
    reg [2:0]  bit_cnt = 7;
    reg [7:0]  shift_out;
    reg        sda_out = 1;
    reg        sda_oe  = 0;      // output enable
    reg [7:0]  pause_cnt = 0;    // delay counter after reset

    assign sda = sda_oe ? sda_out : 1'bz;

    // Phase ticker
    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 0; phase <= 0;
        end else begin
            if (div_cnt == DIV-1) begin
                div_cnt <= 0;
                phase   <= phase + 1;
            end else begin
                div_cnt <= div_cnt + 1;
            end
        end
    end

    // Main FSM (advances on phase == 0, i.e. start of each SCL low period)
    wire tick = (div_cnt == 0) && (phase == 0);

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            scl     <= 1;
            sda_out <= 1;
            sda_oe  <= 0;
            done    <= 0;
            reg_idx <= 0;
            bit_cnt <= 7;
        end else begin
            // Default SCL driven from phase counter
            scl <= phase[1]; // high during phases 2 & 3, low during 0 & 1

            case (state)
                S_IDLE: begin
                    sda_oe  <= 1;
                    sda_out <= 1;           // bus idle = SDA high
                    scl     <= 1;
                    if (tick && !done) state <= S_START;
                end

                // START: SDA falls while SCL is high
                S_START: begin
                    sda_oe  <= 1;
                    sda_out <= 0;
                    scl     <= 1; // Keep SCL high during START
                    if (tick) begin
                        shift_out <= CAM_ADDR;
                        bit_cnt   <= 7;
                        state     <= S_ADDR;
                    end
                end

                // Phase 1: transmit 8-bit device ID (0x42)
                S_ADDR: begin
                    sda_oe  <= 1;
                    sda_out <= shift_out[7];
                    if (tick) begin
                        if (bit_cnt == 0) begin
                            state <= S_ACK1;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt - 1;
                        end
                    end
                end

                // Don't-Care bit after Phase 1
                S_ACK1: begin
                    sda_oe  <= 0; // release - slave may or may not pull low
                    if (tick) begin
                        shift_out <= reg_table[reg_idx][15:8]; // register address
                        bit_cnt   <= 7;
                        state     <= S_REG;
                    end
                end

                // Phase 2: transmit 8-bit register address
                S_REG: begin
                    sda_oe  <= 1;
                    sda_out <= shift_out[7];
                    if (tick) begin
                        if (bit_cnt == 0) begin
                            state <= S_ACK2;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt - 1;
                        end
                    end
                end

                // Don't-Care bit after Phase 2
                S_ACK2: begin
                    sda_oe  <= 0;
                    if (tick) begin
                        shift_out <= reg_table[reg_idx][7:0]; // register value
                        bit_cnt   <= 7;
                        state     <= S_DATA;
                    end
                end

                // Phase 3: transmit 8-bit register value
                S_DATA: begin
                    sda_oe  <= 1;
                    sda_out <= shift_out[7];
                    if (tick) begin
                        if (bit_cnt == 0) begin
                            state <= S_ACK3;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt - 1;
                        end
                    end
                end

                // Don't-Care bit after Phase 3
                S_ACK3: begin
                    sda_oe <= 0;
                    if (tick) state <= S_STOP;
                end

                // STOP: SDA rises while SCL is high.
                //
                // FIX #1 - was checking (phase == 3), which is the SCL-falling
                // quarter.  The non-blocking assignment then registered sda_out=1
                // one clock later, right as SCL dropped - SDA and SCL falling
                // almost simultaneously, which is NOT a valid STOP condition.
                //
                // Correct sequence:
                //   phase 0,1 → SCL low,  SDA low  (setup before SCL rises)
                //   phase 2   → SCL high; register sda_out=1 so SDA rises
                //               at the start of phase 3 (still SCL high)
                //   phase 3   → SCL still high, SDA=1 → valid STOP window
                //   phase 0   → tick fires, SCL falls, move to S_PAUSE
                //               SDA stays 1 (bus released)
                S_STOP: begin
                    sda_oe  <= 1;
                    sda_out <= 0;               // default: hold SDA low
                    if (phase == 2)             // FIX: was (phase == 3)
                        sda_out <= 1;           // SDA rises during SCL-high window
                    if (tick)
                        state <= S_PAUSE;
                end

                // Inter-transaction gap (~2.5 ms with pause_cnt = 250).
                // FIX #2 - the original code did not drive sda_out/sda_oe here,
                // so on the very first tick out of S_STOP the unconditional
                // "sda_out <= 0" from S_STOP would have registered, momentarily
                // pulling SDA low with SCL high - a spurious START condition
                // visible to the camera between every register write.
                // Drive the bus to idle (SDA=1, OE=1) explicitly.
                S_PAUSE: begin
                    sda_oe  <= 1;
                    sda_out <= 1;               // FIX: hold SDA high between writes
                    if (tick) begin
                        if (pause_cnt < 250) begin
                            pause_cnt <= pause_cnt + 1;
                        end else begin
                            pause_cnt <= 0;
                            if (reg_idx == N_REGS - 1) begin
                                state <= S_DONE;
                            end else begin
                                reg_idx <= reg_idx + 1;
                                state   <= S_IDLE;
                            end
                        end
                    end
                end

                S_DONE: begin
                    done    <= 1;
                    sda_oe  <= 0;
                    scl     <= 1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule