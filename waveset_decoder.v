// =========================================================================
// waveset_decoder.v - 全常规测试波形格式 WAVESET 查表与译码模块 (架构级最终版)
// 修正说明：
// 1. 采用全局比较窗口使能命名 act_cmp_win_en，完美契合下游 cmp_formatter。
// 2. 严格分离 R0 的单点指令(L,H,M,V)与视窗开启指令(wL,wH,wM,wV)。
// 3. 恢复所有波形格式的详细注释，确保代码可读性与可维护性。
// =========================================================================

`include "wave_def.vh"

module waveset_decoder #(
    parameter integer PAT_ACT_GROUNP  = 2 // 64bit
)
(
    input  wire [3:0] pattern_index,       // WAVESET 波形索引 (0~15)
    input  wire [32*PAT_ACT_GROUNP-1:0] pattern_act_cfg,
    input  wire [2:0] data_src_sel,        // 调试/数据源选择
    
    // ---------------------------------------------------------------------
    // 物理驱动控制信号 (1-bit 原生)
    // ---------------------------------------------------------------------
    output reg        act_e0,              // e0: 使能/三态控制 (0 = Driver ON, 1 = High-Z)
    output reg        act_e1,              // e1: 驱动数据 (1 = High, 0 = Low)
    output reg        act_e2,              // e2: 辅助驱动数据
    output reg        act_e3,              // e3: 辅助驱动数据
    output reg        act_e4,              // e4: 驱动数据 (1 = High, 0 = Low)
    output reg        act_e5,              // e5: 使能/三态控制 (0 = Driver ON, 1 = High-Z)
    
    // ---------------------------------------------------------------------
    // 物理比对控制信号 (架构级优化命名)
    // ---------------------------------------------------------------------
    output reg        act_r0_en,           // r0 比对使能
    output reg [1:0]  act_r0_mode,         // r0 比对模式 (00:L, 01:H, 10:M, 11:V)
    output reg        act_cmp_win_en,      // 全局比较窗口使能 (1 = 窗口比对模式, 0 = 独立Strobe模式)
    
    output reg        act_r1_en,           // r1 比对使能
    output reg [1:0]  act_r1_mode          // r1 比对模式
);

    // 1. 符号别名定义
    localparam N  = `ACT_N;        // No Action
    localparam _0 = `ACT_DRV_0;    // Drive Low
    localparam _1 = `ACT_DRV_1;    // Drive High
    localparam Z  = `ACT_F_OFF;    // Force Off (高阻)
    localparam F  = `ACT_F_ON;     // Force On  (开驱动)
	//
    localparam L  = `ACT_CMP_L;    // Compare Low R0,R1  [00]
    localparam H  = `ACT_CMP_H;    // Compare High R0,R1 
    localparam V  = `ACT_CMP_V;    // Compare Valid R0,R1  
    localparam M  = `ACT_CMP_M;    // Compare Mid-band R0,R1 
	//
    localparam wL = `ACT_WIN_L;    // Window Low Open  R0
    localparam wH = `ACT_WIN_H;    // Window High Open R0
    localparam wV = `ACT_WIN_V;    // Window Valid Open R0
    localparam wM = `ACT_WIN_M;    // Window Mid Open R0
    localparam C  = `ACT_CLOSE;    // Close Window Compare R0

    // 内部动作变量与解算变量
    reg [3:0] pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1;
    reg       lut_e0, lut_e1, lut_e2, lut_e3, lut_e4, lut_e5;
    reg       lut_r0_en, lut_r1_en;
    reg [1:0] lut_r0_mode, lut_r1_mode;
    reg       lut_cmp_win_en; // 内部全局视窗使能寄存器

    // 2. WAVESET 查找表
   always @(*) begin
    case (pattern_index)
        //                                                       				  //D0   D1   D2   D3   D4   D5   R0   R1
        // 格式 0: NRZ (不回零)
        4'h0: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  F, _1,  N,  N,  N,  Z,  N,  N };

        // 格式 1: DNRZ (延迟不回零)
        4'h1: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  Z, _1,  F,  N,  N,  Z,  N,  N };

        // 格式 2: RZ (回零脉冲)
       // 4'h2: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  F, _1, _0, _1, _0,  Z,  H,  L };
		4'h2: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  F, _1, _0, _1, _0,  Z,  H,wH };


        // 格式 3: RO (回一脉冲)
        4'h3: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  F, _0, _1,  N,  N,  Z,  N,  N };

        // 格式 4: SBC (反相包围波形)
        4'h4: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  F, _0, _1, _0,  N,  Z,  N,  N };

        // 格式 5: High-Z (全高阻/输入模式)
        4'h5: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  Z,  N,  N,  N,  N,  Z,  N,  N };

        // 格式 6: Edge Compare (单点采样比对)
        4'h6: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  Z,  N,  N,  N,  N,  Z,  H,  N };

        // 格式 7: Window Compare (窗口持续比对)
        4'h7: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {  Z,  N,  N,  N,  N,  Z, wL,  C };

        // 格式 9: 自定义扩展预留 (动态配置透传)
        4'h9: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = {
            pattern_act_cfg[31:28], // D0
            pattern_act_cfg[27:24], // D1
            pattern_act_cfg[23:20], // D2
            pattern_act_cfg[19:16], // D3
            pattern_act_cfg[15:12], // D4
            pattern_act_cfg[11:8],  // D5
            pattern_act_cfg[7:4],   // R0
            pattern_act_cfg[3:0]    // R1
        };

        default: {pat_e0, pat_e1, pat_e2, pat_e3, pat_e4, pat_e5, pat_r0, pat_r1} = { N, N, N, N, N, N, N, N };
    endcase
end
    

    // 3. 内部物理解码逻辑
    always @(*) begin
        lut_e0 = (pat_e0 == F) ? 1'b0 : 1'b1;
        lut_e5 = (pat_e5 == F) ? 1'b0 : 1'b1;
		//
        lut_e1 = (pat_e1 == _1);
        lut_e2 = (pat_e2 == _1);
        lut_e3 = (pat_e3 == _1);
        lut_e4 = (pat_e4 == _1);
    end

    // --- 比对边沿 r0 解码 (分离单点与窗口，激活 act_cmp_win_en) ---
    always @(*) begin
        case (pat_r0)
            // 单点比对 (Strobe)
            L:       begin lut_r0_en = 1'b1; lut_r0_mode = 2'b00; lut_cmp_win_en = 1'b0; end
            H:       begin lut_r0_en = 1'b1; lut_r0_mode = 2'b01; lut_cmp_win_en = 1'b0; end
            M:       begin lut_r0_en = 1'b1; lut_r0_mode = 2'b10; lut_cmp_win_en = 1'b0; end
            V:       begin lut_r0_en = 1'b1; lut_r0_mode = 2'b11; lut_cmp_win_en = 1'b0; end
            // 视窗开启 (Window Open)
            wL:      begin lut_r0_en = 1'b1; lut_r0_mode = 2'b00; lut_cmp_win_en = 1'b1; end
            wH:      begin lut_r0_en = 1'b1; lut_r0_mode = 2'b01; lut_cmp_win_en = 1'b1; end
            wM:      begin lut_r0_en = 1'b1; lut_r0_mode = 2'b10; lut_cmp_win_en = 1'b1; end
            wV:      begin lut_r0_en = 1'b1; lut_r0_mode = 2'b11; lut_cmp_win_en = 1'b1; end
            // 默认屏蔽
            default: begin lut_r0_en = 1'b0; lut_r0_mode = 2'b00; lut_cmp_win_en = 1'b0; end
        endcase
    end

    // --- 比对边沿 r1 解码 ---
    always @(*) begin
        case (pat_r1)
            L:       begin lut_r1_en = 1'b1; lut_r1_mode = 2'b00; end // 单点 Compare Low
            H:       begin lut_r1_en = 1'b1; lut_r1_mode = 2'b01; end // 单点 Compare High
            M:       begin lut_r1_en = 1'b1; lut_r1_mode = 2'b10; end // 单点 Compare Mid-band
            V:       begin lut_r1_en = 1'b1; lut_r1_mode = 2'b11; end // 单点 Compare Valid
            C:       begin lut_r1_en = 1'b1; lut_r1_mode = 2'b00; end // 关窗口脉冲
            default: begin lut_r1_en = 1'b0; lut_r1_mode = 2'b00; end 
        endcase
    end

    // 4. MUX 级联与调试模式覆写逻辑
    always @(*) begin
        act_e0         = lut_e0;
        act_e1         = lut_e1;
        act_e2         = lut_e2;
        act_e3         = lut_e3;
        act_e4         = lut_e4;
        act_e5         = lut_e5;
        act_r0_en      = lut_r0_en;
        act_r0_mode    = lut_r0_mode;
        act_cmp_win_en = lut_cmp_win_en; // 透传全局视窗使能
        act_r1_en      = lut_r1_en;
        act_r1_mode    = lut_r1_mode;

        // Debug 模式强制覆盖
        case (data_src_sel)
            `SRC_PAT: begin end // 正常模式
            `SRC_TRIS: begin
                act_e0 = 1'b1;
                act_e5 = 1'b1;
            end
            `SRC_PATHI, `SRC_ALLHI: begin
                act_e0 = 1'b0; act_e5 = 1'b0; 
                act_e1 = 1'b1; act_e4 = 1'b1;
            end
            `SRC_PATLO, `SRC_ALLLO: begin
                act_e0 = 1'b0; act_e5 = 1'b0; 
                act_e1 = 1'b0; act_e4 = 1'b0;
            end
            default: begin
                act_e0 = 1'b1;
                act_e5 = 1'b1;
            end
        endcase
    end

endmodule