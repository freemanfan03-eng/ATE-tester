// =========================================================================
// drv_formatter.v - 专职 DRV 驱动波形展开引擎 (资源优化版, 首窗口修复)
// =========================================================================
// 修复记录:
//  [FIX] 原版用 r_data_valid (= r_running 延迟一拍) 去清零 r_drv_parallel,
//        导致 trigger 后第 0 个 64-UI 窗口 (T1 拍, r_running=1 而 r_data_valid=0)
//        的有效 comb_drv_parallel 被写成 0, 首周期里落在前 64 UI 内的边沿
//        (如 E1=45) 被推迟到 64 UI。
//        现改为直接用 r_running 门控输出寄存器, 删除 r_data_valid。
//        其余逻辑与优化版完全一致。
//
// 相对"高位裁切版"消除的冗余运算:
//  [1] 32 位 ptr 寄存器 + (ptr+DW) 32 位加法 + 32 位比较 + 32 位减法 + 3:1 选择
//      + ui_left 的 "24 位比较 + 24 位减法"
//      -> 一个 r_ui_left 递减计数器 + 一个 25 位加法器 (边界/非边界共用)
//         + 提前一拍寄存的 r_cross / r_cross_part 标志。
//  [2] 4 个 25 位 "edge - ptr" 减法器 + 4 个 25 位 "edge + ui_left" 加法器
//      + 8 个 18 位高位或归约 + 符号判断
//      -> 每路边沿仅 1 个 (EDGE_WIDTH+1) 位小加法 + 1 个 11 位饱和减 64
//         (减 64 不触及低 6 位), 饱和标志 r_sat / r_nesat 寄存, 无需每拍归约。
//      下一向量掩码只在 ui_left < DATA_WIDTH 时有效, 只需 SH 位加法。
//  [3] curr_vector_end_act: 4 个比较器 + 优先级链在装载时算一次, 存 r_end_act;
//      比较器输出同时供 trigger 装载与 r_nvld 寄存使用 (共用同一组比较器)。
//      "edge < DATA_WIDTH" 复用 edge >= DATA_WIDTH 的反相, 不再单独比较。
//  [4] 576 位 (4x64 当前 + 4x64 下一 + 64 is_next) 温度计译码改为 "分层译码":
//      out[j] = sat | (v_hi > a) | ((v_hi == a) & (v_lo > b)),  j = {a, b}
//      高/低位组的比较 (各 <= 3 输入) 被同组的 8 个输出共享,
//      每个输出位只剩一个 3 输入函数 (相邻两位可被工具合并进同一个 LUT6),
//      sat / part 等标志折进共享项, 不再逐位多占 1~2 个输入。
//  [5] 数据通路寄存器不带 rst_n 使能, 减少 CE 扇出与控制集。
//
// 使用约束:
//  - DATA_WIDTH   >= 4
//  - EDGE_WIDTH   >= $clog2(DATA_WIDTH) + 1
//  - PERIOD_WIDTH >= $clog2(DATA_WIDTH) + 1
//  - 周期输入被钳位到 >= DATA_WIDTH (与原版一致)
// =========================================================================
`include "wave_def.vh"

module drv_formatter #(
    parameter integer DATA_WIDTH   = 64,
    parameter integer EDGE_WIDTH   = 16,
    parameter integer PERIOD_WIDTH = 24
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // 流控接口
    input  wire                      trigger_sync,
    input  wire [PERIOD_WIDTH-1:0]   period_ui_in,

    // DRV 的 4 个驱动边沿时间戳 (E1 ~ E4)
    input  wire [EDGE_WIDTH-1:0]     act_edge_1_ui, act_edge_2_ui,
    input  wire [EDGE_WIDTH-1:0]     act_edge_3_ui, act_edge_4_ui,

    // DRV 的 4 个 1-bit 驱动目标电平 (由上游直接译码提供)
    input  wire                      act_e1, act_e2, act_e3, act_e4,

    // 输出接口
    output wire                      next_vector_req,
    output wire [DATA_WIDTH-1:0]     drv_parallel_data // 直接挂载到 GT DRV TX 并行口
);

    // =========================================================================
    // 0. 常量与位宽
    // =========================================================================
    localparam integer SH = (DATA_WIDTH > 1) ? $clog2(DATA_WIDTH) : 1;
    localparam integer LW = SH / 2;          // 分层译码: 低位组宽度 (64 -> 3)
    localparam integer HW = SH - LW;         // 分层译码: 高位组宽度 (64 -> 3)
    localparam integer EW = EDGE_WIDTH;
    localparam integer PW = PERIOD_WIDTH;

    localparam [PW-1:0] DW_P   = DATA_WIDTH;        // 周期钳位下限
    localparam [PW:0]   DW_PP  = DATA_WIDTH;        // 同上, 多 1 位进位
    localparam [PW:0]   DW2_PP = 2 * DATA_WIDTH;
    localparam [EW:0]   DW_E   = DATA_WIDTH;
    localparam [EW:0]   DW2_E  = 2 * DATA_WIDTH;

    // 分层温度计译码: out[j] = sat | (v > j), 0 <= j < DATA_WIDTH
    //   j = {a, b},  v = {vh, vl}
    //   v > j  <=>  (vh > a) | ((vh == a) & (vl > b))
    function automatic [DATA_WIDTH-1:0] thermo;
        input            sat;
        input [SH-1:0]   v;
        integer          j;
        reg [HW-1:0]     vh, a;
        reg [LW-1:0]     vl, b;
        begin
            vh = v[SH-1:LW];
            vl = v[LW-1:0];
            for (j = 0; j < DATA_WIDTH; j = j + 1) begin
                a = j >> LW;
                b = j;
                thermo[j] = sat | (vh > a) | ((vh == a) & (vl > b));
            end
        end
    endfunction

    // =========================================================================
    // 1. 状态寄存器声明
    // =========================================================================
    reg                r_running;
    reg                r_cross;        // == 原 vector_boundary_crossed (已寄存)
    reg                r_cross_part;   // r_cross && ui_left < DATA_WIDTH
    reg [PW-1:0]       r_ui_left;      // == 原 period - ptr
    reg                r_prev_drv_data;
    reg                r_end_act;      // == 原 curr_vector_end_act (装载时预计算)
    reg [PW-1:0]       r_next_period;  // 已钳位
    reg [4:1]          r_curr_act;
    reg [4:1]          r_next_act;
    reg                next_vector_req_reg;

    wire [EW-1:0]      edge_in [1:4];
    assign edge_in[1] = act_edge_1_ui;
    assign edge_in[2] = act_edge_2_ui;
    assign edge_in[3] = act_edge_3_ui;
    assign edge_in[4] = act_edge_4_ui;
    wire [4:1]         act_in = {act_e4, act_e3, act_e2, act_e1};

    wire [4:1]         vld_in;         // 输入侧: 边沿 < 钳位后周期
    wire [4:1]         vld_nx;         // 寄存后
    wire [DATA_WIDTH-1:0] mask_c [1:4];
    wire [DATA_WIDTH-1:0] mask_n [1:4];

    // 周期钳位 (trigger 装载与影子寄存共用一份)
    wire [PW-1:0] period_clamped = (period_ui_in < DW_P) ? DW_P : period_ui_in;

    // =========================================================================
    // 2. 向量边界/剩余 UI 计数 (控制寄存器, 异步复位与原版一致)
    // =========================================================================
    // 边界周期: ui_sum = ui_left + next_period ; 非边界周期: ui_sum = ui_left
    // 新 ui_left = ui_sum - DATA_WIDTH
    // 新 cross   = (ui_sum <= 2*DATA_WIDTH)
    // 新 part    = (ui_sum <  2*DATA_WIDTH)
    wire [PW:0] ui_sum = {1'b0, r_ui_left}
                       + (r_cross ? {1'b0, r_next_period} : {(PW+1){1'b0}});
    wire [PW:0] ui_dec = ui_sum - DW_PP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_running       <= 1'b0;
            r_cross         <= 1'b0;
            r_cross_part    <= 1'b0;
            r_ui_left       <= DW_P;               // 原复位: period=DATA_WIDTH, ptr=0
            r_prev_drv_data <= 1'b0;
        end else if (trigger_sync) begin
            r_running       <= 1'b1;
            r_ui_left       <= period_clamped;
            r_cross         <= (period_ui_in <= DW_P);
            r_cross_part    <= 1'b0;               // 钳位后 ui_left >= DATA_WIDTH
            r_prev_drv_data <= 1'b0;
        end else if (r_running) begin
            r_ui_left       <= ui_dec[PW-1:0];
            r_cross         <= (ui_sum <= DW2_PP);
            r_cross_part    <= (ui_sum <  DW2_PP);
            if (r_cross)
                r_prev_drv_data <= r_end_act;
        end
    end

    // 握手信号 (与原版等价: !running 时清零)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_vector_req_reg <= 1'b0;
        end else begin
            next_vector_req_reg <= (r_running & trigger_sync) | r_cross;
        end
    end
    assign next_vector_req = next_vector_req_reg;

    // =========================================================================
    // 3. 数据通路影子寄存器 / 当前向量电平 (无复位, 无 rst_n 使能)
    // =========================================================================
    wire end_act_trig =
        vld_in[4] ? act_e4 :
        vld_in[3] ? act_e3 :
        vld_in[2] ? act_e2 :
        vld_in[1] ? act_e1 : 1'b0;                // trigger 时 prev=0

    wire end_act_cross =
        vld_nx[4] ? r_next_act[4] :
        vld_nx[3] ? r_next_act[3] :
        vld_nx[2] ? r_next_act[2] :
        vld_nx[1] ? r_next_act[1] : r_end_act;    // prev = 旧向量终态

    always @(posedge clk) begin
        r_next_period <= period_clamped;
        r_next_act    <= act_in;

        if (trigger_sync) begin
            r_curr_act <= act_in;
            r_end_act  <= end_act_trig;
        end else if (r_cross) begin
            r_curr_act <= r_next_act;
            r_end_act  <= end_act_cross;
        end
    end

    // =========================================================================
    // 4. 逐边沿: 输入打拍 / 相对边沿 / 掩码 (E1 ~ E4)
    // =========================================================================
    genvar k;
    generate
        for (k = 1; k <= 4; k = k + 1) begin : gen_edge
            // ---- 输入侧影子寄存 (对应原 r_next_edge) ----
            wire         esat_in = (edge_in[k] >= DW_E);          // edge >= DATA_WIDTH
            reg [EW-1:0] r_nedge;
            reg          r_nesat;
            reg          r_nvld;
            assign vld_in[k] = (edge_in[k] < period_ui_in) | ~esat_in;
            assign vld_nx[k] = r_nvld;

            always @(posedge clk) begin
                r_nedge <= edge_in[k];
                r_nesat <= esat_in;
                r_nvld  <= vld_in[k];
            end

            // ---- 当前向量: 相对当前窗口起点的剩余边沿 ----
            reg [EW-1:0] r_rel;         // max(edge - ptr, 0)
            reg          r_sat;         // r_rel >= DATA_WIDTH

            // 边界周期: 新向量剩余边沿 = next_edge + ui_left (ui_left<=DW) 再减一个窗口
            // 非边界周期: 当前剩余边沿 再减一个窗口
            wire [EW:0] sum_n  = {1'b0, r_nedge}
                               + {{(EW-SH){1'b0}}, r_ui_left[SH:0]};
            wire [EW:0] base   = r_cross ? sum_n : {1'b0, r_rel};
            wire [EW:0] rel_nx = (base > DW_E) ? (base - DW_E) : {(EW+1){1'b0}};
            wire        sat_nx = (base >= DW2_E);

            always @(posedge clk) begin
                if (trigger_sync) begin
                    r_rel <= edge_in[k];
                    r_sat <= esat_in;
                end else begin
                    r_rel <= rel_nx[EW-1:0];
                    r_sat <= sat_nx;
                end
            end

            // ---- 当前窗口掩码: i < r_rel ----
            assign mask_c[k] = thermo(r_sat, r_rel[SH-1:0]);

            // ---- 下一向量掩码 (仅 ui_left < DATA_WIDTH 时被使用): i < ui_left + edge ----
            wire [SH:0] nsum = {1'b0, r_nedge[SH-1:0]} + {1'b0, r_ui_left[SH-1:0]};
            assign mask_n[k] = thermo(r_nesat | nsum[SH], nsum[SH-1:0]);
        end
    endgenerate

    // =========================================================================
    // 5. 并行 DRV 展开引擎
    // =========================================================================
    // ui_gt[i] = (ui_left[SH-1:0] > i);  is_next_vec = part & ~ui_gt  (== 原 i >= ui_left)
    wire [DATA_WIDTH-1:0] ui_gt = thermo(1'b0, r_ui_left[SH-1:0]);
    wire [DATA_WIDTH-1:0] comb_drv_parallel;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_wave_bits
            wire is_next_vec = r_cross_part & ~ui_gt[i];

            wire curr_drv_bit =
                mask_c[1][i] ? r_prev_drv_data :
                mask_c[2][i] ? r_curr_act[1]   :
                mask_c[3][i] ? r_curr_act[2]   :
                mask_c[4][i] ? r_curr_act[3]   :
                               r_curr_act[4];

            wire next_drv_bit =
                mask_n[1][i] ? r_end_act       :
                mask_n[2][i] ? r_next_act[1]   :
                mask_n[3][i] ? r_next_act[2]   :
                mask_n[4][i] ? r_next_act[3]   :
                               r_next_act[4];

            assign comb_drv_parallel[i] = is_next_vec ? next_drv_bit : curr_drv_bit;
        end
    endgenerate

    // =========================================================================
    // 6. 最终打拍输出
    // =========================================================================
    // [FIX] 直接用 r_running 门控: trigger 后第一拍 (r_running=1) 的 comb 数据
    //       即为第 0 个窗口的有效数据, 不能再被多延迟一拍的 valid 清零。
    reg [DATA_WIDTH-1:0] r_drv_parallel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_drv_parallel <= {DATA_WIDTH{1'b0}};
        end else if (!r_running) begin
            r_drv_parallel <= {DATA_WIDTH{1'b0}};
        end else begin
            r_drv_parallel <= comb_drv_parallel;
        end
    end

    assign drv_parallel_data = r_drv_parallel;

endmodule