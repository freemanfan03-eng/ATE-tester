// =============================================================================
// File Name  : gtx_drp_map.vh
// Target HW  : Xilinx 7 Series FPGAs GTX Transceiver (Kintex-7 / Virtex-7)
// Reference  : UG476 (7 Series FPGAs GTX/GTH Transceivers User Guide)
// Address Width: 9-bit (9'h000 ~ 9'h1FF)
// Data Width   : 16-bit
// =============================================================================
// new_val = (drp_rd_data & ~`DRP_MASK_RXOUT_DIV) | (16'h0001 & `DRP_MASK_RXOUT_DIV);
`ifndef GTX_DRP_MAP_VH
`define GTX_DRP_MAP_VH

// =============================================================================
// 1. 线速率与输出分频器 (Line Rate & Output Dividers)
// =============================================================================
// 说明: 该寄存器是改变 TX/RX 线速率最常用的地址
// Bit[6:4] : TXOUT_DIV  (3'b000:/1, 3'b001:/2, 3'b010:/4, 3'b011:/8, 3'b100:/16)
// Bit[2:0] : RXOUT_DIV  (3'b000:/1, 3'b001:/2, 3'b010:/4, 3'b011:/8, 3'b100:/16)
`define DRP_ADDR_OUT_DIV            9'h088
`define DRP_MASK_TXOUT_DIV          16'h0070
`define DRP_MASK_RXOUT_DIV          16'h0007

// =============================================================================
// 2. CPLL 配置与分频器 (CPLL Settings)
// =============================================================================
// CPLL 参考时钟分频器 (CPLL_REFCLK_DIV)
// Bit[12:8] : 5'b10000 (/1), 5'b00000 (/2)
`define DRP_ADDR_CPLL_REFCLK_DIV   9'h05E
`define DRP_MASK_CPLL_REFCLK_DIV   16'h1F00

// CPLL 反馈分频器 (CPLL_FBDIV & CPLL_FBDIV_45)
// Bit[15]   : CPLL_FBDIV_45 (0: /4, 1: /5)
// Bit[14:8] : CPLL_FBDIV    (1: /1, 2: /2, 3: /3, 4: /4, 5: /5)
`define DRP_ADDR_CPLL_FBDIV        9'h05F
`define DRP_MASK_CPLL_FBDIV_45     16'h8000
`define DRP_MASK_CPLL_FBDIV        16'h7F00

// =============================================================================
// 3. QPLL 配置 (QPLL Settings - Quad 共享)
// =============================================================================
// QPLL 反馈分频器 (QPLL_FBDIV)
// Bit[14:8] : QPLL_FBDIV
`define DRP_ADDR_QPLL_FBDIV        9'h036
`define DRP_MASK_QPLL_FBDIV        16'h7F00

// QPLL 参考时钟分频器 (QPLL_REFCLK_DIV)
// Bit[12:8] : QPLL_REFCLK_DIV
`define DRP_ADDR_QPLL_REFCLK_DIV   9'h033
`define DRP_MASK_QPLL_REFCLK_DIV   16'h1F00

// =============================================================================
// 4. RX 时钟数据恢复与相干控制 (RX CDR & Phase Interpolator)
// =============================================================================
// RX CDR 参数控制 (针对不同线速率/数据类型调整 CDR 环路带宽)
`define DRP_ADDR_RXCDR_CFG_0        9'h0A8  // RXCDR_CFG[15:0]
`define DRP_ADDR_RXCDR_CFG_1        9'h0A9  // RXCDR_CFG[31:16]
`define DRP_ADDR_RXCDR_CFG_2        9'h0AA  // RXCDR_CFG[47:32]
`define DRP_ADDR_RXCDR_CFG_3        9'h0AB  // RXCDR_CFG[63:48]
`define DRP_ADDR_RXCDR_CFG_4        9'h0AC  // RXCDR_CFG[72:64]

// RX 相位插值器控制 (RX Phase Interpolator)
// Bit[1:0] : RX_PI_CFG
`define DRP_ADDR_RX_PI_CFG          9'h09A

// =============================================================================
// 5. PCS 内部数据位宽设置 (PCS Internal Data Width)
// =============================================================================
// Bit[13:11] : RX_DATA_WIDTH (3'b011: 16-bit, 3'b101: 20-bit, 3'b110: 32-bit, 3'b111: 40-bit)
// Bit[5:3]   : TX_DATA_WIDTH (3'b011: 16-bit, 3'b101: 20-bit, 3 me: 32-bit, 3'b111: 40-bit)
`define DRP_ADDR_DATA_WIDTH         9'h011
`define DRP_MASK_RX_DATA_WIDTH      16'h3800
`define DRP_MASK_TX_DATA_WIDTH      16'h0038

// =============================================================================
// 6. RX 均衡器与 DFE 配置 (RX Equalizer / DFE / LPM)
// =============================================================================
`define DRP_ADDR_RX_DFE_KL_CFG2     9'h012  // DFE 增益模式
`define DRP_ADDR_RX_LPM_CFG         9'h029  // LPM (Low Power Mode) 自动均衡参数

// =============================================================================
// 7. TX 预加重与驱动控制 (TX Driver & Equalization)
// =============================================================================
// Bit[6:4] : TXPRECURSOR  (前摆)
// Bit[3:0] : TXPOSTCURSOR (后摆)
`define DRP_ADDR_TX_EQ              9'h07A
`define DRP_MASK_TXPRECURSOR        16'h0070
`define DRP_MASK_TXPOSTCURSOR       16'h000F

`endif // GTX_DRP_MAP_VH