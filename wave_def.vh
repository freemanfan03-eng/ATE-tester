// =========================================================================
// wave_def.vh - ATE 动作编码与控制宏定义
// =========================================================================
`ifndef WAVE_DEF_VH
`define WAVE_DEF_VH

	// =========================================================================
	// ATE WAVESET Action Macro Definitions (4-bit width)
	// =========================================================================

	// 1. 无动作 / 默认
	`define ACT_N       	4'h0  // No Action / Do nothing

	// 2. 驱动类动作 (Drive)
	`define ACT_DRV_0   	4'h1  // Drive Low (驱低，当驱动器使能时)
	`define ACT_DRV_1   	4'h2  // Drive High (驱高，当驱动器使能时)
	`define ACT_F_OFF 		4'h3 // Force Off / Disable or tristate output driver
	`define ACT_F_ON  		4'h4 // Force On / Enable the output driver

	// 3. 常规边沿比对类动作 (Edge Compare - R0, R1)
	`define ACT_CMP_L   4'h5  // Compare Low (VDUT < VOL)
	`define ACT_CMP_H   4'h6  // Compare High (VDUT > VOH)
	`define ACT_CMP_V   4'h7  // Compare Valid ((VDUT > VOH) or (VDUT < VOL))
	`define ACT_CMP_M   4'h8  // Compare Mid-band (VOL < VDUT < VOH)

	// 4. 窗口比对类动作 (Window Compare - R0 开启，R1 关闭)
	`define ACT_WIN_L   4'h9  // Compare Low Window (VDUT < VOL)
	`define ACT_WIN_H   4'hA  // Compare High Window (VDUT > VOH)
	`define ACT_WIN_V   4'hB  // Compare Valid Window ((VDUT > VOH) or (VDUT < VOL))
	`define ACT_WIN_M   4'hC  // Compare Mid-band Window (VOL < VDUT < VOH)
	`define ACT_CLOSE   4'hD  // Close Window Compare (End of window compare)

	// -------------------------------------------------------------------------
	// 4. 数据源 / 调试控制选择定义 (Data Source Select)
	// -------------------------------------------------------------------------
	`define SRC_TRIS   3'd0  // 三态模式 (Tristate / High-Z)
	`define SRC_PAT    3'd1  // 正常图形查表模式 (WAVESET)
	`define SRC_PATHI  3'd2  // Debug 强制高 (Path High)
	`define SRC_PATLO  3'd3  // Debug 强制低 (Path Low)
	`define SRC_ALLHI  3'd4  // 全局强制高且忽略周期
	`define SRC_ALLLO  3'd5  // 全局强制低且忽略周期

`endif // WAVE_DEF_VH