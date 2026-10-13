// =========================================================================
// rcv_formatter.v - RCV 接收波形展开引擎 (资源优化版, 首窗口修复)
// =========================================================================
// 修复记录:
//  [FIX] 原版用 r_data_valid (= r_running 延迟一拍) 去清零 r_rcv_parallel,
//        导致 trigger 后第 0 个 64-UI 窗口 (T1 拍, r_running=1 而 r_data_valid=0)
//        的有效 comb_rcv_parallel 被写成 0, 首向量前 64 UI 的内容丢失。
//        现改为直接用 r_running 门控输出寄存器, 删除 r_data_valid。
//        其余逻辑与优化版完全一致。
//
// 相对上一版再消除的冗余:
//  [1] 温度计译码改为 "分层译码" (当前掩码 2x64 + 下一掩码 2x64 + is_next 64 共 320 位):
//        out[j] = sat | (v_hi > a) | ((v_hi == a) & (v_lo > b)),  j = {a, b}
//      高/低位组的比较 (各 <= 3 输入) 被同组 8 个输出共享, 每位只剩 3 输入函数,
//      相邻两位可被工具合并进同一个 LUT6; sat / part 折进共享项, 不再逐位占输入。
//      下一向量掩码的 nsum 进位位 (nsum[SH]) 并入 sat 项, 译码输入由 SH+1 位降为 SH 位。
//  [2] "edge < DATA_WIDTH" 直接复用 "edge >= DATA_WIDTH" 的反相 (esat_in),
//      不再为每路边沿多放一个比较器; esat_in 同时供 r_nesat / r_sat / vld_in 使用。
//  [3] 周期钳位 (period_ui_in < DATA_WIDTH ? DATA_WIDTH : period_ui_in)
//      显式只生成一份, trigger 装载与 r_next_period 共用。
//
// 沿用上一版的结构优化:
//  - r_ui_left 递减计数器取代 ptr; r_cross / r_cross_part 提前一拍寄存
//  - 当前边沿存相对剩余值 r_rel + r_sat, 下一向量掩码只需 SH 位小加法
//  - 有效终态 r_end_act 在装载时预计算; 数据通路寄存器无 rst_n 使能
//  - 输出寄存器为标准 "异步复位 + 同步清零" 写法
//
// 使用约束:
//  - DATA_WIDTH   >= 4
//  - EDGE_WIDTH   >= $clog2(DATA_WIDTH) + 1
//  - PERIOD_WIDTH >= $clog2(DATA_WIDTH) + 1
//  - 原版边沿寄存器固定为 16 位; 本版按 EDGE_WIDTH 参数化,
//    EDGE_WIDTH = 16 (默认) 时与原版完全一致。
//  - 周期输入被钳位到 >= DATA_WIDTH (与原版一致)
// =========================================================================
`include "wave_def.vh"

module rcv_formatter #(
    parameter integer DATA_WIDTH   = 64,
    parameter integer EDGE_WIDTH   = 16,
    parameter integer PERIOD_WIDTH = 24
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          trigger_sync,
    input  wire [PERIOD_WIDTH-1:0]       period_ui_in,

    // RCV 专属的 2 个边沿 (E0, E5)
    input  wire [EDGE_WIDTH-1:0]         act_edge_0_ui,
    input  wire [EDGE_WIDTH-1:0]         act_edge_5_ui,
    input  wire                          act_e0,
    input  wire                          act_e5,

    output wire                          next_vector_req,
    output wire [DATA_WIDTH-1:0]         rcv_parallel_data
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
    // 1. 状态寄存器声明   (下标 0 -> E0, 下标 1 -> E5)
    // =========================================================================
    reg                r_running;
    reg                r_cross;        // == 原 vector_boundary_crossed (已寄存)
    reg                r_cross_part;   // r_cross && ui_left < DATA_WIDTH
    reg [PW-1:0]       r_ui_left;      // == 原 period - ptr
    reg                r_prev_rcv_data;
    reg                r_end_act;      // == 原 curr_vector_end_act (装载时预计算)
    reg [PW-1:0]       r_next_period;  // 已钳位
    reg [1:0]          r_curr_act;
    reg [1:0]          r_next_act;
    reg                next_vector_req_reg;

    wire [EW-1:0]      edge_in [0:1];
    assign edge_in[0] = act_edge_0_ui;
    assign edge_in[1] = act_edge_5_ui;
    wire [1:0]         act_in = {act_e5, act_e0};

    wire [1:0]         vld_in;         // 输入侧: 边沿 < 钳位后周期
    wire [1:0]         vld_nx;         // 寄存后 (对应原 r_next_edge 的有效性)
    wire [DATA_WIDTH-1:0] mask_c [0:1];
    wire [DATA_WIDTH-1:0] mask_n [0:1];

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
            r_prev_rcv_data <= 1'b0;
        end else if (trigger_sync) begin
            r_running       <= 1'b1;
            r_ui_left       <= period_clamped;
            r_cross         <= (period_ui_in <= DW_P);
            r_cross_part    <= 1'b0;               // 钳位后 ui_left >= DATA_WIDTH
            r_prev_rcv_data <= 1'b0;
        end else if (r_running) begin
            r_ui_left       <= ui_dec[PW-1:0];
            r_cross         <= (ui_sum <= DW2_PP);
            r_cross_part    <= (ui_sum <  DW2_PP);
            if (r_cross)
                r_prev_rcv_data <= r_end_act;
        end
    end

    // 握手逻辑 (与原版等价: !running 时清零)
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
    // 优先取 E5, E5 超出周期(禁用)则取 E0, 都禁用则保持上一向量终态
    wire end_act_trig =
        vld_in[1] ? act_e5 :
        vld_in[0] ? act_e0 : 1'b0;                // trigger 时 prev=0

    wire end_act_cross =
        vld_nx[1] ? r_next_act[1] :
        vld_nx[0] ? r_next_act[0] : r_end_act;    // prev = 旧向量终态

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
    // 4. 逐边沿: 输入打拍 / 相对边沿 / 掩码 (k=0: E0, k=1: E5)
    // =========================================================================
    genvar k;
    generate
        for (k = 0; k < 2; k = k + 1) begin : gen_edge
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
    // 5. 并行 RCV 展开引擎
    // =========================================================================
    // ui_gt[i] = (ui_left[SH-1:0] > i);  is_next_vec = part & ~ui_gt  (== 原 i >= ui_left)
    wire [DATA_WIDTH-1:0] ui_gt = thermo(1'b0, r_ui_left[SH-1:0]);
    wire [DATA_WIDTH-1:0] comb_rcv_parallel;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_wave_bits
            wire is_next_vec = r_cross_part & ~ui_gt[i];

            wire curr_rcv_bit =
                mask_c[0][i] ? r_prev_rcv_data :
                mask_c[1][i] ? r_curr_act[0]   :
                               r_curr_act[1];

            // 下一个向量的起始基准电平为旧向量有效终态 r_end_act
            wire next_rcv_bit =
                mask_n[0][i] ? r_end_act       :
                mask_n[1][i] ? r_next_act[0]   :
                               r_next_act[1];

            assign comb_rcv_parallel[i] = is_next_vec ? next_rcv_bit : curr_rcv_bit;
        end
    endgenerate

    // =========================================================================
    // 6. 最终打拍输出
    // =========================================================================
    // [FIX] 直接用 r_running 门控: trigger 后第一拍 (r_running=1) 的 comb 数据
    //       即为第 0 个窗口的有效数据, 不能再被多延迟一拍的 valid 清零。
    reg [DATA_WIDTH-1:0] r_rcv_parallel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_rcv_parallel <= {DATA_WIDTH{1'b0}};
        end else if (!r_running) begin
            r_rcv_parallel <= {DATA_WIDTH{1'b0}};
        end else begin
            r_rcv_parallel <= comb_rcv_parallel;
        end
    end

    assign rcv_parallel_data = r_rcv_parallel;

endmodule