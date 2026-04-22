# OV7670 → Basys 3 Camera Project
## Wiring, Bring-up, and Troubleshooting Guide

---

## 1. Physical Wiring Table

| FPGA Pin | Basys 3 Header | Camera Signal | Notes |
|----------|----------------|---------------|-------|
| P17 | JB-1 | D0 | pixel data LSB |
| N17 | JB-2 | D1 | |
| M19 | JB-3 | D2 | |
| M18 | JB-4 | D3 | |
| L17 | JB-7 | D4 | |
| K17 | JB-8 | D5 | |
| C16 | JB-9 | D6 | |
| B16 | JB-10| D7 | pixel data MSB |
| A17 | JC-1 | HREF | active HIGH = valid line |
| A16 | JC-2 | PCLK | pixel clock (camera → FPGA) |
| R18 | JC-3 | PWDN | tie LOW (camera powered on) |
| P18 | JC-4 | RST  | active LOW reset |
| A14 | JC-7 | SCL  | SCCB clock (open-drain, 4.7kΩ pull-up to 3.3V) |
| A15 | JC-8 | SDA  | SCCB data  (open-drain, 4.7kΩ pull-up to 3.3V) |
| B15 | JC-9 | VSYNC| frame sync |
| C15 | JC-10| XCLK | master clock (FPGA → camera) |

### Power
- VCC → 3.3V from Basys 3 header  
- GND → GND from Basys 3 header

> ⚠️ **Important**: Add 4.7kΩ pull-up resistors from SCL and SDA to 3.3V.  
> The OV7670 SCCB lines are open-drain; without pull-ups the lines float.

---

## 2. Vivado Project Setup

### Step 1 – Create the Clocking Wizard IP
1. Open IP Catalog → Clocking Wizard
2. Name it `clk_wiz_0`
3. Input: 100 MHz
4. Output 1: **25.000 MHz** (VGA pixel clock)
5. Output 2: **24.000 MHz** (camera XCLK)
6. Output 3: **50.000 MHz** (SCCB/logic)
7. Enable `locked` output port

### Step 2 – Add Source Files
Add all `.v` files to the project:
- `camera_top.v` (top module)
- `sccb_master.v`
- `cam_capture.v`
- `frame_buffer.v`
- `vga_sync.v`

### Step 3 – Add Constraints
Add `Basys3_camera.xdc` as the constraints file.

### Step 4 – Set Top Module
Right-click `camera_top` in the Sources panel → Set as Top.

---

## 3. Simulation (Before Synthesis)

Run testbenches in Vivado Simulator or ModelSim:

```
# VGA sync test
iverilog -o tb_vga tb_vga_sync.v vga_sync.v && vvp tb_vga

# Camera capture test
iverilog -o tb_cam tb_cam_capture.v cam_capture.v && vvp tb_cam
```

Expected output:
- VGA: exactly **1050 HSYNC pulses** and **2 VSYNC pulses** in 2 frames
- Camera: **12 pixels** correctly assembled from the 4×3 mini-frame

---

## 4. Bring-up Sequence (Hardware)

### LED Status Key
| LED | Meaning |
|-----|---------|
| LED0 | PLL locked (should be ON within 1ms of power-up) |
| LED1 | SCCB config done (should turn ON ~50ms after reset) |
| LED2 | Camera VSYNC toggling (confirms camera is running) |
| LED3 | Camera HREF pulsing (confirms pixel data arriving) |

### Step-by-step
1. **Program the FPGA** via Vivado Hardware Manager.
2. **Check LED0** – if dark, PLL failed (check clock constraints).
3. **Wait 1–2 seconds** for SCCB to finish writing all registers → **LED1 ON**.
4. **Check LED2** – should blink at ~30 Hz (VSYNC). If dark, camera is not running (check XCLK and power).
5. **Check LED3** – rapid blinking during active lines.
6. **Connect VGA monitor** – you should see a live 320×240 image (pixel-doubled to 640×480).

---

## 5. Filter Switch Reference

| SW[1] | SW[0] | Filter |
|-------|-------|--------|
| 0     | 0     | Raw camera feed |
| 0     | 1     | Grayscale |
| 1     | 0     | Color negative (invert) |
| 1     | 1     | Red channel only |

---

## 6. Common Problems & Fixes

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No image, gray screen | SCCB not working | Check pull-up resistors on SCL/SDA |
| Image very dark/bright | Wrong register values | Adjust COM9 (AGC) register |
| Image frozen / wrong colors | Byte alignment off | Check VSYNC → byte_sel reset in cam_capture |
| Monitor says "No Signal" | VGA timing wrong | Verify clk_wiz_0 outputs exactly 25 MHz |
| BRAM timing warnings | Clock domain crossing | Ensure set_false_path in XDC is correct |
| Upside-down image | Camera orientation | Set register 0x1E (MVFP) bit[4]=1 to flip |

---

## 7. Module Block Diagram

```
100MHz ──► clk_wiz_0 ──► 25MHz ──► vga_sync ──► VGA monitor
                    │                    │
                    └──► 24MHz ──► cam_xclk (OV7670)
                    │
                    └──► 50MHz ──► sccb_master ──► OV7670 config
                                        │
OV7670 ──► cam_capture (pclk domain) ──► frame_buffer ──► filter mux ──► VGA RGB
              HREF, VSYNC, D[7:0]         (BRAM)            sw[1:0]
```

---

## 8. Memory Budget

| Item | Size |
|------|------|
| Frame buffer (320×240×12bit) | 921,600 bits ≈ **900 Kbits** |
| Basys 3 total BRAM | 1,800 Kbits |
| Remaining for extra features | ~900 Kbits |
