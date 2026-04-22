## ============================================================
## Basys3_camera.xdc  –  Pin constraints
## OV7670 camera + VGA output on Basys 3
## ============================================================

## -------- System clock (100 MHz onboard oscillator) ---------
set_property PACKAGE_PIN W5   [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
create_clock -add -name sys_clk_pin -period 10.00 [get_ports clk100]

## -------- Camera pixel data bus (D0..D7) --------------------
## D0
set_property PACKAGE_PIN P17  [get_ports {cam_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[0]}]
## D1
set_property PACKAGE_PIN N17  [get_ports {cam_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[1]}]
## D2
set_property PACKAGE_PIN M19  [get_ports {cam_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[2]}]
## D3
set_property PACKAGE_PIN M18  [get_ports {cam_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[3]}]
## D4
set_property PACKAGE_PIN L17  [get_ports {cam_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[4]}]
## D5
set_property PACKAGE_PIN K17  [get_ports {cam_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[5]}]
## D6
set_property PACKAGE_PIN C16  [get_ports {cam_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[6]}]
## D7
set_property PACKAGE_PIN B16  [get_ports {cam_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[7]}]

## -------- Camera control/sync signals -----------------------
## HREF (Horizontal Reference)
set_property PACKAGE_PIN A17  [get_ports cam_href]
set_property IOSTANDARD LVCMOS33 [get_ports cam_href]
## PCLK (Pixel Clock – input from camera)
set_property PACKAGE_PIN A16  [get_ports cam_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pclk]
## PWDN (Power Down – output to camera, keep LOW)
set_property PACKAGE_PIN R18  [get_ports cam_pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pwdn]
## RST (Reset – output to camera, active LOW)
set_property PACKAGE_PIN P18  [get_ports cam_reset]
set_property IOSTANDARD LVCMOS33 [get_ports cam_reset]
## SCL (SCCB clock – output)
set_property PACKAGE_PIN A14  [get_ports cam_scl]
set_property IOSTANDARD LVCMOS33 [get_ports cam_scl]
## SDA (SCCB data – bidirectional)
set_property PACKAGE_PIN A15  [get_ports cam_sda]
set_property IOSTANDARD LVCMOS33 [get_ports cam_sda]
## VSYNC (from camera)
set_property PACKAGE_PIN B15  [get_ports cam_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports cam_vsync]
## XCLK (master clock to camera – output from FPGA)
set_property PACKAGE_PIN C15  [get_ports cam_xclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_xclk]

## -------- VGA connector -------------------------------------
set_property PACKAGE_PIN G19  [get_ports vga_r[0]]
set_property PACKAGE_PIN H19  [get_ports vga_r[1]]
set_property PACKAGE_PIN J19  [get_ports vga_r[2]]
set_property PACKAGE_PIN N19  [get_ports vga_r[3]]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

set_property PACKAGE_PIN J17  [get_ports vga_g[0]]
set_property PACKAGE_PIN H17  [get_ports vga_g[1]]
set_property PACKAGE_PIN G17  [get_ports vga_g[2]]
set_property PACKAGE_PIN D17  [get_ports vga_g[3]]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

set_property PACKAGE_PIN N18  [get_ports vga_b[0]]
set_property PACKAGE_PIN L18  [get_ports vga_b[1]]
set_property PACKAGE_PIN K18  [get_ports vga_b[2]]
set_property PACKAGE_PIN J18  [get_ports vga_b[3]]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

set_property PACKAGE_PIN P19  [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property PACKAGE_PIN R19  [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

## -------- Slide switches (filter select) --------------------
set_property PACKAGE_PIN V17  [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16  [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[1]}]

## -------- Status LEDs ----------------------------------------
set_property PACKAGE_PIN U16  [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN E19  [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN U19  [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN V19  [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

## -------- CDC false paths (camera → VGA clock domain) -------
## The BRAM handles CDC; tell the timing engine not to analyze across domains
set_false_path -from [get_clocks -of_objects [get_ports cam_pclk]] \
               -to   [get_clocks clk_out1_clk_wiz_0]
