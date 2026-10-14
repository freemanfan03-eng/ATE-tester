// =========================================================================
// waveform_comparator.v - 高速波形并行比对器 (OP Code 极简执行端)
// =========================================================================
// 设计说明：
// 上游 cmp_formatter 已将复杂的物理区间与多模式纠缠坍塌为 192-bit 指令：
// - cmp_win_mask (64-bit) : 决定该 UI 是否需要进行判定
// - cmp_op_code (128-bit) : 2-bit 决定该 UI 的物理判定法则
// 
// 本模块直接与 ADATE318 引脚电子进行对接，物理判决法则严格遵循波形规范表：
// 00 (L): 测低，要求 VDUT < VOL (即 CL == 0)
// 01 (H): 测高，要求 VDUT > VOH (即 CH == 1)
// 10 (M): 高阻，要求 VOL < VDUT < VOH (即 CH == 0 且 CL == 1)
// 11 (V): 有效，要求 VDUT > VOH 或 VDUT < VOL (即 CH == 1 或 CL == 0)
// =========================================================================

module compare_engine #(
    parameter integer DATA_WIDTH = 64
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    // --- 降维后的 192-bit 全新控制总线 ---
    input  wire [DATA_WIDTH-1:0]        cmp_win_mask,       // 比对窗口掩码 (1: 执行比对, 0: 屏蔽)
    input  wire [2*DATA_WIDTH-1:0]      cmp_op_code,        // 物理指令码 (00:L, 01:H, 10:M, 11:V)
    
    // --- 来自 GT / ADATE318 的实时采样回传数据 ---
    input  wire [DATA_WIDTH-1:0]        cmp_h_in,           // CH: V_DUT > VOH 则输出 1
    input  wire [DATA_WIDTH-1:0]        cmp_l_in,           // CL: V_DUT > VOL 则输出 1
    
    // --- 最终比对结果输出 ---
    output wire [DATA_WIDTH-1:0]        bit_pass_vector,    // 按位比对结果 (1: Pass, 0: Fail)
    output wire                         channel_fail_flag,  // 通道总体 Fail 标志 (0: Pass, 1: Fail)
    output reg  [DATA_WIDTH-1:0]        fail_capture_reg    // 故障捕获寄存器 (用于波形抓取分析)
);

    wire [DATA_WIDTH-1:0] bit_pass;
    wire [DATA_WIDTH-1:0] bit_fail;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_bit_comp
            // 1. 拆包：精准提取当前微观 UI 的窗口使能与指令码
            wire       win = cmp_win_mask[i];
            wire [1:0] op  = cmp_op_code[2*i +: 2];
            
            // 提取当前 UI 的物理采样值
            wire       ch  = cmp_h_in[i];
            wire       cl  = cmp_l_in[i];

            // 2. 判决：极简 4-Way LUT，没有任何多余逻辑
            reg actual_match;
            always @(*) begin
                case (op)
                    2'b00: actual_match = (cl == 1'b0);                   // L模式 (00): 低于低阈值
                    2'b01: actual_match = (ch == 1'b1);                   // H模式 (01): 高于高阈值
                    2'b10: actual_match = (ch == 1'b0) && (cl == 1'b1);   // M模式 (10): 夹在中间带
                    2'b11: actual_match = (ch == 1'b1) || (cl == 1'b0);   // V模式 (11): 两侧有效带
                endcase
            end

            // 3. 掩码屏蔽：不在窗口内的 UI 强行 Pass
            assign bit_pass[i] = win ?  actual_match : 1'b1;
            assign bit_fail[i] = win ? ~actual_match : 1'b0;
        end
    endgenerate

    // =========================================================================
    // 归约与锁存网络 (Fail Capture)
    // =========================================================================
    
    // 按位透传，供给前台 Trace 追踪
    assign bit_pass_vector = bit_pass;
    
    // 通道级归约：只要 64 UI 内发生哪怕 1 个 Fail 尖峰，全局 Flag 立刻拉高
    assign channel_fail_flag = ~( &bit_pass );

    // 故障捕获寄存器：同步打拍，保留最原始的 Fail 分布图景，供给失效分析 (FA) 软件使用
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fail_capture_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            fail_capture_reg <= bit_fail;
        end
    end

endmodule