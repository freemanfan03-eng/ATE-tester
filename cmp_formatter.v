// =========================================================================
// cmp_formatter.v - ATE 高吞吐比对窗口掩码展开引擎 (完美对齐边界流水线版 + 智能 STB 选择)
// =========================================================================
`include "wave_def.vh"

module cmp_formatter #(
    parameter integer DATA_WIDTH      = 64,
    parameter integer EDGE_WIDTH      = 16,
    parameter integer PERIOD_WIDTH    = 24,
    parameter integer STROBE_WIDTH_UI = 10
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          trigger_sync,
    input  wire [PERIOD_WIDTH-1:0]       period_ui_in,
    input  wire [EDGE_WIDTH-1:0]         cmp_edge_r0_ui,
    input  wire [EDGE_WIDTH-1:0]         cmp_edge_r1_ui,
    input  wire                          act_r0,
    input  wire                          act_r1,
    input  wire [1:0]                    act_r0_mode,
    input  wire [1:0]                    act_r1_mode,
    input  wire                          act_cmp_win_en,
    output wire                          next_vector_req,
    output wire [DATA_WIDTH-1:0]         cmp_win_mask,
    output wire [2*DATA_WIDTH-1:0]       cmp_op_code
);
    localparam integer SH_W  = 6;                 // log2(DATA_WIDTH)
    localparam integer REL_W = EDGE_WIDTH + 1;      // 边沿 + STROBE 不溢出
    localparam integer OFF_W = REL_W + 1;
    localparam [PERIOD_WIDTH-1:0] DW_P = DATA_WIDTH;

    // 核心修改：根据周期大小简单直接地决定 STB 宽度（小周期给 2，大周期给 STROBE_WIDTH_UI 或 8）
    wire [3:0] STB = (period_ui_in < DATA_WIDTH) ? 4'd2 : STROBE_WIDTH_UI;

    // 饱和温度码：n >= DATA_WIDTH 时全 1，否则低 n 位为 1
    function [DATA_WIDTH-1:0] thermo;
        input [OFF_W-1:0] n;
        begin
            if (n >= DATA_WIDTH) thermo = {DATA_WIDTH{1'b1}};
            else                 thermo = ~({DATA_WIDTH{1'b1}} << n[SH_W-1:0]);
        end
    endfunction

    // max(x - DATA_WIDTH, 0)
    function [REL_W-1:0] sat_sub;
        input [OFF_W-1:0] x;
        begin
            sat_sub = (x > DATA_WIDTH) ? (x - DATA_WIDTH) : {REL_W{1'b0}};
        end
    endfunction

    // 安全循环求余函数（带防死锁与 X 态保护）
    function automatic [PERIOD_WIDTH-1:0] mod_safe;
        input [PERIOD_WIDTH+6:0] val;
        input [PERIOD_WIDTH-1:0] p;
        reg [PERIOD_WIDTH+6:0] temp;
        integer safety;
        begin
            if (p <= 1) begin
                mod_safe = {PERIOD_WIDTH{1'b0}};
            end else if (val === { (PERIOD_WIDTH+7){1'bx} } || p === {PERIOD_WIDTH{1'bx}}) begin
                mod_safe = {PERIOD_WIDTH{1'b0}};
            end else begin
                temp = val;
                safety = 0;
                while (temp >= p && safety < 128) begin
                    temp = temp - p;
                    safety = safety + 1;
                end
                mod_safe = temp[PERIOD_WIDTH-1:0];
            end
        end
    endfunction

    // =========================================================================
    // 0. 小周期判定与专用累加器
    // =========================================================================
    wire is_small_period = (period_ui_in < DATA_WIDTH);
    wire [PERIOD_WIDTH-1:0] period_safe = (period_ui_in == 0) ? 1'd1 : period_ui_in;

    reg [PERIOD_WIDTH-1:0] r_small_phase;
    reg                    r_running_small;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_small_phase   <= {PERIOD_WIDTH{1'b0}};
            r_running_small <= 1'b0;
        end else if (trigger_sync) begin
            r_small_phase   <= {PERIOD_WIDTH{1'b0}};
            r_running_small <= is_small_period;
        end else if (r_running_small && is_small_period) begin
            r_small_phase <= mod_safe(r_small_phase + DATA_WIDTH, period_safe);
        end else if (!is_small_period) begin
            r_running_small <= 1'b0;
        end
    end

    // =========================================================================
    // 1. 输入侧派生参数（严格听从全局视窗使能，保护 STB 生效）
    // =========================================================================
    wire                      in_both    = act_r0 & act_r1;
    wire                      in_act_any = act_r0 | act_r1;
    
    // 回归规范，视窗模式严格由 act_cmp_win_en 与双边沿共同决定
    wire                      in_is_win  = in_both & act_cmp_win_en;
    wire                      in_has_s2  = in_both & ~act_cmp_win_en;
    
    wire [REL_W-1:0]          in_s1      = act_r0 ? {1'b0, cmp_edge_r0_ui} : {1'b0, cmp_edge_r1_ui};
    // 当不在视窗模式时，e1 严格由起始边沿加动态选择的 STB 决定
    wire [REL_W-1:0]          in_e1      = in_is_win ? {1'b0, cmp_edge_r1_ui} : (in_s1 + STB);
    wire [REL_W-1:0]          in_s2      = {1'b0, cmp_edge_r1_ui};
    wire [REL_W-1:0]          in_e2      = in_s2 + STB;
    wire [1:0]                in_mode1   = act_r0 ? act_r0_mode : act_r1_mode;
    wire [1:0]                in_mode2   = act_r1_mode;
    wire [PERIOD_WIDTH-1:0]   in_period  = period_ui_in;

    // =========================================================================
    // 2. 大周期专用状态机与流水线对齐的影子寄存器
    // =========================================================================
    reg                       r_is_running;
    reg [PERIOD_WIDTH-1:0]    r_ui_left;

    reg                       r_c_act_any, r_c_has_s2;
    reg [1:0]                 r_c_mode1,   r_c_mode2;
    reg [REL_W-1:0]           r_c_s1, r_c_e1, r_c_s2, r_c_e2;
    reg [REL_W-1:0]           r_pe;
    reg [1:0]                 r_prev_spillover_mode;

    reg [PERIOD_WIDTH-1:0]    r_n_period;
    reg                       r_n_act_any, r_n_has_s2;
    reg [1:0]                 r_n_mode1,   r_n_mode2;
    reg [REL_W-1:0]           r_n_s1, r_n_e1, r_n_s2, r_n_e2;

    wire vector_boundary_crossed = r_is_running && (r_ui_left <= DATA_WIDTH);

    // 握手请求信号
    reg next_vector_req_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_vector_req_reg <= 1'b0;
        end else begin
            next_vector_req_reg <= (r_is_running || r_running_small) && (trigger_sync || vector_boundary_crossed);
        end
    end
    assign next_vector_req = next_vector_req_reg;

    // 流水线延迟一拍：匹配图形发生器响应延迟，防止边界 Mask 信号丢失
    reg r_req_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) r_req_d1 <= 1'b0;
        else        r_req_d1 <= next_vector_req_reg;
    end

    wire [SH_W:0]             ul7      = r_ui_left[SH_W:0];
    wire [OFF_W-1:0]          n_off_s1 = {1'b0, r_n_s1} + ul7;
    wire [OFF_W-1:0]          n_off_e1 = {1'b0, r_n_e1} + ul7;
    wire [OFF_W-1:0]          n_off_s2 = {1'b0, r_n_s2} + ul7;
    wire [OFF_W-1:0]          n_off_e2 = {1'b0, r_n_e2} + ul7;

    wire [REL_W-1:0]          c_maxend     = r_c_has_s2 ? r_c_e2    : r_c_e1;
    wire [1:0]                c_spill_mode = r_c_has_s2 ? r_c_mode2 : r_c_mode1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_is_running          <= 1'b0;
            r_ui_left             <= DW_P;
            r_c_act_any <= 1'b0;  r_c_has_s2 <= 1'b0;
            r_c_mode1   <= 2'b00; r_c_mode2  <= 2'b00;
            r_c_s1 <= {REL_W{1'b0}}; r_c_e1 <= STB;
            r_c_s2 <= {REL_W{1'b0}}; r_c_e2 <= STB;
            r_pe                  <= {REL_W{1'b0}};
            r_prev_spillover_mode <= 2'b00;

            r_n_period  <= DW_P;
            r_n_act_any <= 1'b0;  r_n_has_s2 <= 1'b0;
            r_n_mode1   <= 2'b00; r_n_mode2  <= 2'b00;
            r_n_s1 <= {REL_W{1'b0}}; r_n_e1 <= STB;
            r_n_s2 <= {REL_W{1'b0}}; r_n_e2 <= STB;
        end else if (is_small_period) begin
            r_is_running <= 1'b0;
        end else begin
            // 影子寄存器跟随 r_req_d1 锁存，完美对齐 Sequencer 响应延迟
            if (trigger_sync || r_req_d1) begin
                r_n_period  <= in_period;
                r_n_act_any <= in_act_any; r_n_has_s2 <= in_has_s2;
                r_n_mode1   <= in_mode1;   r_n_mode2  <= in_mode2;
                r_n_s1 <= in_s1; r_n_e1 <= in_e1;
                r_n_s2 <= in_s2; r_n_e2 <= in_e2;
            end

            if (trigger_sync) begin
                r_is_running          <= 1'b1;
                r_ui_left             <= in_period;
                r_c_act_any <= in_act_any; r_c_has_s2 <= in_has_s2;
                r_c_mode1   <= in_mode1;   r_c_mode2  <= in_mode2;
                r_c_s1 <= in_s1; r_c_e1 <= in_e1;
                r_c_s2 <= in_s2; r_c_e2 <= in_e2;
                r_pe                  <= {REL_W{1'b0}};
                r_prev_spillover_mode <= 2'b00;

            end else if (vector_boundary_crossed) begin
                r_ui_left             <= r_n_period + ul7 - DW_P;
                r_c_act_any <= r_n_act_any; r_c_has_s2 <= r_n_has_s2;
                r_c_mode1   <= r_n_mode1;   r_c_mode2  <= r_n_mode2;
                r_c_s1 <= sat_sub(n_off_s1); r_c_e1 <= sat_sub(n_off_e1);
                r_c_s2 <= sat_sub(n_off_s2); r_c_e2 <= sat_sub(n_off_e2);
                r_pe                  <= sat_sub({1'b0, c_maxend});
                r_prev_spillover_mode <= c_spill_mode;

            end else if (r_is_running) begin
                r_ui_left <= r_ui_left - DW_P;
                r_c_s1 <= sat_sub({1'b0, r_c_s1}); r_c_e1 <= sat_sub({1'b0, r_c_e1});
                r_c_s2 <= sat_sub({1'b0, r_c_s2}); r_c_e2 <= sat_sub({1'b0, r_c_e2});
                r_pe   <= sat_sub({1'b0, r_pe});
            end
        end
    end

    wire r_running_all = r_is_running || r_running_small;
    reg r_data_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_data_valid <= 1'b0;
        end else begin
            r_data_valid <= r_running_all;
        end
    end

    // =========================================================================
    // 3. 大周期掩码计算
    // =========================================================================
    wire [DATA_WIDTH-1:0] next_vec_mask = (r_ui_left >= DATA_WIDTH) ? {DATA_WIDTH{1'b0}} :
                                          ~({DATA_WIDTH{1'b1}} << r_ui_left[SH_W-1:0]);

    wire [DATA_WIDTH-1:0] mask_c1   = r_c_act_any ? (thermo({1'b0, r_c_e1}) & ~thermo({1'b0, r_c_s1})) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_c2   = r_c_has_s2  ? (thermo({1'b0, r_c_e2}) & ~thermo({1'b0, r_c_s2})) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_n1   = r_n_act_any ? (thermo(n_off_e1) & ~thermo(n_off_s1)) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_n2   = r_n_has_s2  ? (thermo(n_off_e2) & ~thermo(n_off_s2)) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_prev = thermo({1'b0, r_pe});

    // =========================================================================
    // 4. 双模并行比对展开与指令熔铸
    // =========================================================================
    wire [DATA_WIDTH-1:0]      ui_win_mask_comb;
    wire [2*DATA_WIDTH-1:0]    ui_op_code_comb;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_cmp_mask_bits
            // 模式 A：小周期高频循环比对计算
            wire [PERIOD_WIDTH-1:0] small_ui = mod_safe(r_small_phase + i, period_safe);
            wire small_s1 = in_act_any && (small_ui >= in_s1) && (small_ui < in_e1);
            wire small_s2 = in_has_s2  && (small_ui >= in_s2) && (small_ui < in_e2);
            wire small_win = small_s1 || small_s2;
            wire [1:0] small_op = small_s2 ? in_mode2 : in_mode1;

            // 模式 B：大周期标准双向量无缝跨界计算
            wire is_next_vec = next_vec_mask[i];
            wire match_c2    = mask_c2[i];
            wire match_n2    = mask_n2[i];
            wire match_p     = mask_prev[i];
            wire match_curr  = mask_c1[i] | match_c2;
            wire match_next  = mask_n1[i] | mask_n2;

            wire large_win   = is_next_vec ? match_next : (match_curr | match_p);
            wire [1:0] op_curr = match_c2 ? r_c_mode2 : r_c_mode1;
            wire [1:0] op_next = match_n2 ? r_n_mode2 : r_n_mode1;
            wire [1:0] large_op = is_next_vec ? op_next : (match_p ? r_prev_spillover_mode : op_curr);

            // 双模自适应分流选择
            assign ui_win_mask_comb[i] = is_small_period ? small_win : large_win;
            assign ui_op_code_comb[2*i +: 2] = is_small_period ? small_op : large_op;
        end
    endgenerate

    // =========================================================================
    // 5. 打拍输出
    // =========================================================================
    reg [DATA_WIDTH-1:0]    r_cmp_win_mask;
    reg [2*DATA_WIDTH-1:0]  r_cmp_op_code;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_cmp_win_mask <= {DATA_WIDTH{1'b0}};
            r_cmp_op_code  <= {(2*DATA_WIDTH){1'b0}};
        end else if (!r_data_valid) begin
            r_cmp_win_mask <= {DATA_WIDTH{1'b0}};
            r_cmp_op_code  <= {(2*DATA_WIDTH){1'b0}};
        end else begin
            r_cmp_win_mask <= ui_win_mask_comb;
            r_cmp_op_code  <= ui_op_code_comb;
        end
    end

    assign cmp_win_mask = r_cmp_win_mask;
    assign cmp_op_code  = r_cmp_op_code;

endmodule