module top (
  input ADATE318_SPI0_BUSY_AB27,
  inout [0:0]ADATE318_SPI0_CS_AE29,
  inout ADATE318_SPI0_MISO_AB29,
  inout ADATE318_SPI0_MOSI_AD27,
  inout ADATE318_SPI0_SCLK_AB30,
  output [0:0]ADATE_PE_RST_N_AD29,
  input ATE_CMPH0_N,
  input ATE_CMPH0_P_AA4,
  input ATE_CMPL0_N,
  input ATE_CMPL0_P_Y6,
  output ATE_DAT0_N,
  output ATE_DAT0_P_V2,
  output ATE_RCV0_N,
  output ATE_RCV0_P_Y2,
  input DDR_REF_AE10_clk_n,
  input DDR_REF_AE10_clk_p,
  output LED0_U27,
  output LED1_U28,
  output LED2_T25,
  output LED3_U25,
  input ext_reset_in_T21,
  input gt_refclk_pad_n_in,
  input gt_refclk_pad_p_in
	
);
   
   
   (* dont_touch="true" *)
   design_1_wrapper design_1_wrapper
   (.ADATE318_SPI0_BUSY_AB27(ADATE318_SPI0_BUSY_AB27),
    .ADATE318_SPI0_CS_AE29(ADATE318_SPI0_CS_AE29),
    .ADATE318_SPI0_MISO_AB29(ADATE318_SPI0_MISO_AB29),
    .ADATE318_SPI0_MOSI_AD27(ADATE318_SPI0_MOSI_AD27),
    .ADATE318_SPI0_SCLK_AB30(ADATE318_SPI0_SCLK_AB30),
    .ADATE_PE_RST_N_AD29(ADATE_PE_RST_N_AD29),
    .ATE_CMPH0_N(ATE_CMPH0_N),
    .ATE_CMPH0_P_AA4(ATE_CMPH0_P_AA4),
    .ATE_CMPL0_N(ATE_CMPL0_N),
    .ATE_CMPL0_P_Y6(ATE_CMPL0_P_Y6),
    .ATE_DAT0_N(ATE_DAT0_N),
    .ATE_DAT0_P_V2(ATE_DAT0_P_V2),
    .ATE_RCV0_N(ATE_RCV0_N),
    .ATE_RCV0_P_Y2(ATE_RCV0_P_Y2),
    .DDR_REF_AE10_clk_n(DDR_REF_AE10_clk_n),
    .DDR_REF_AE10_clk_p(DDR_REF_AE10_clk_p),
    .LED0_U27(LED0_U27),
    .LED1_U28(LED1_U28),
    .LED2_T25(LED2_T25),
    .LED3_U25(LED3_U25),
    .ext_reset_in_T21(ext_reset_in_T21),
    .gt_refclk_pad_n_in(gt_refclk_pad_n_in),
    .gt_refclk_pad_p_in(gt_refclk_pad_p_in)
	);
	
	

endmodule