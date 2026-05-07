// ============================================================
// sccb_master.v  -  SCCB (I2C-like) master for OV7670 config
// Writes a fixed register table then asserts done.
// Clock: 50 MHz input → ~100 kHz SCCB clock
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
    // Register init table  [addr, value]
    // Minimal set for RGB565, 320x240 (QVGA), 30fps
    // --------------------------------------------------------
    reg [15:0] reg_table [0:22];
    initial begin
        reg_table[0]  = 16'h1280; // COM7  - reset
        reg_table[1]  = 16'h1280; // COM7  - reset (double for safety)
        reg_table[2]  = 16'h1204; // COM7  - RGB output
        reg_table[3]  = 16'h1100; // CLKRC - no prescaler
        reg_table[4]  = 16'h0C00; // COM3
        reg_table[5]  = 16'h3E00; // COM14 - no scaling/PCLK div
        reg_table[6]  = 16'h8C02; // RGB444 → 0 = off; RGB565 mode
        reg_table[7]  = 16'h0400; // COM1  - no CCIR
        reg_table[8]  = 16'h40D0; // COM15 - RGB 565, full range
        reg_table[9]  = 16'h14IA; // COM9  - AGC x4 (I = 0x1A)
        reg_table[10] = 16'h4FB3; // MTX1
        reg_table[11] = 16'h50B3; // MTX2
        reg_table[12] = 16'h5100; // MTX3
        reg_table[13] = 16'h523D; // MTX4
        reg_table[14] = 16'h53A7; // MTX5
        reg_table[15] = 16'h54E4; // MTX6
        reg_table[16] = 16'h589E; // MTXS
        reg_table[17] = 16'h3DC8; // COM13 - gamma, UV
        reg_table[18] = 16'h1714; // HSTART
        reg_table[19] = 16'h1802; // HSTOP
        reg_table[20] = 16'h3200; // HREF
        reg_table[21] = 16'h1903; // VSTART
        reg_table[22] = 16'h1A7B; // VSTOP
    end
    localparam N_REGS = 23;

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

    reg [3:0]  state  = S_IDLE;
    reg [7:0]  div_cnt = 0;
    reg [1:0]  phase  = 0;      // 0=SCL_LOW,1=SCL_RISE,2=SCL_HIGH,3=SCL_FALL
    reg [4:0]  reg_idx = 0;
    reg [2:0]  bit_cnt = 7;
    reg [7:0]  shift_out;
    reg        sda_out = 1;
    reg        sda_oe  = 0;     // output enable

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

    // Main FSM (advances on phase == 0, i.e. start of each SCL low)
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
            // Default SCL from phase
            scl <= phase[1]; // high during phase 2&3, low during 0&1

            case (state)
                S_IDLE: begin
                    sda_oe  <= 1;
                    sda_out <= 1;
                    scl     <= 1;
                    if (tick && !done) state <= S_START;
                end

                // START condition: SDA falls while SCL high
                S_START: begin
                    sda_oe  <= 1;
                    sda_out <= 0;
                    // after this SCL goes low, send address
                    if (tick) begin
                        shift_out <= CAM_ADDR;
                        bit_cnt   <= 7;
                        state     <= S_ADDR;
                    end
                end

                S_ADDR: begin
                    sda_oe  <= 1;
                    sda_out <= shift_out[7];
                    if (tick) begin
                        if (bit_cnt == 0) begin
                            state   <= S_ACK1;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt - 1;
                        end
                    end
                end

                S_ACK1: begin
                    sda_oe  <= 0; // release for slave ACK
                    if (tick) begin
                        shift_out <= reg_table[reg_idx][15:8]; // register addr
                        bit_cnt   <= 7;
                        state     <= S_REG;
                    end
                end

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

                S_ACK2: begin
                    sda_oe  <= 0;
                    if (tick) begin
                        shift_out <= reg_table[reg_idx][7:0]; // register value
                        bit_cnt   <= 7;
                        state     <= S_DATA;
                    end
                end

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

                S_ACK3: begin
                    sda_oe <= 0;
                    if (tick) state <= S_STOP;
                end

                // STOP: SDA rises while SCL high
                S_STOP: begin
                    sda_oe  <= 1;
                    sda_out <= 0;
                    if (phase == 2) sda_out <= 1; // rise while SCL high
                    if (tick) begin
                        state <= S_PAUSE;
                    end
                end

                // Short gap between register writes (~500us)
                S_PAUSE: begin
                    // reuse div_cnt cycles × 200 for a long pause
                    if (tick) begin
                        if (reg_idx == N_REGS-1) begin
                            state <= S_DONE;
                        end else begin
                            reg_idx <= reg_idx + 1;
                            state   <= S_IDLE;
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