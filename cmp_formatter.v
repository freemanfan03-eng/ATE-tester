// =========================================================================
// cmp_formatter.v - ATE 高吞吐比对窗口掩码展开引擎 (符合 Table 8 规范的完整版)
// 接口：缩减为 192-bit (64-bit win_mask + 128-bit op_code)
// 核心：无缝支持 单边沿、双独立边沿(如 R0=L, R1=H)、以及连续视窗(如 R0=wL, R1=C)
// 修正说明：同步适配 waveset_decoder 的 act_cmp_win_en 全局视窗使能信号。
// =========================================================================
// =========================================================================
// cmp_formatter.v - ATE 高吞吐比对窗口掩码展开引擎 (IEEE 1364-2001 标准版)
// =========================================================================
`include "wave_def.vh"

module cmp_formatter #(
    parameter integer DATA_WIDTH      = 64,
    parameter integer EDGE_WIDTH      = 16,
    parameter integer PERIOD_WIDTH    = 24,
    parameter integer STROBE_WIDTH_UI = 10
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       trigger_sync,
    input  wire [PERIOD_WIDTH-1:0]    period_ui_in,
    input  wire [EDGE_WIDTH-1:0]      cmp_edge_r0_ui,
    input  wire [EDGE_WIDTH-1:0]      cmp_edge_r1_ui,
    input  wire                       act_r0,
    input  wire                       act_r1,
    input  wire [1:0]                 act_r0_mode,
    input  wire [1:0]                 act_r1_mode,
    input  wire                       act_cmp_win_en,
    output wire                       next_vector_req,
    output wire [DATA_WIDTH-1:0]      cmp_win_mask,
    output wire [2*DATA_WIDTH-1:0]    cmp_op_code
);
    localparam integer SH_W  = 6;               // log2(DATA_WIDTH)
    localparam integer REL_W = EDGE_WIDTH + 1;  // 边沿 + STROBE 不溢出
    localparam integer OFF_W = REL_W + 1;
    localparam [PERIOD_WIDTH-1:0] DW_P = DATA_WIDTH;
    localparam [REL_W-1:0]        STB  = STROBE_WIDTH_UI;

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

    // =========================================================================
    // 1. 输入侧派生（只算一份，同时供 next / trigger 加载）
    // =========================================================================
    wire                    in_both    = act_r0 & act_r1;
    wire                    in_act_any = act_r0 | act_r1;
    wire                    in_is_win  = in_both &  act_cmp_win_en;
    wire                    in_has_s2  = in_both & ~act_cmp_win_en;
    wire [REL_W-1:0]        in_s1      = act_r0 ? {1'b0, cmp_edge_r0_ui} : {1'b0, cmp_edge_r1_ui};
    wire [REL_W-1:0]        in_e1      = in_is_win ? {1'b0, cmp_edge_r1_ui} : (in_s1 + STB);
    wire [REL_W-1:0]        in_s2      = {1'b0, cmp_edge_r1_ui};
    wire [REL_W-1:0]        in_e2      = in_s2 + STB;
    wire [1:0]              in_mode1   = act_r0 ? act_r0_mode : act_r1_mode;
    wire [1:0]              in_mode2   = act_r1_mode;
    wire [PERIOD_WIDTH-1:0] in_period  = (period_ui_in < DATA_WIDTH) ? DW_P : period_ui_in;

    // =========================================================================
    // 2. 状态寄存器
    //    r_ui_left = period - ptr（原 ui_left，直接寄存，取代 ptr/period）
    //    r_c_xx    = max(edge - ptr, 0)，当前向量相对本拍基址的饱和偏移
    //    r_pe      = max(spillover - ptr, 0)
    // =========================================================================
    reg                     r_is_running;
    reg [PERIOD_WIDTH-1:0]  r_ui_left;

    reg                     r_c_act_any, r_c_has_s2;
    reg [1:0]               r_c_mode1,   r_c_mode2;
    reg [REL_W-1:0]         r_c_s1, r_c_e1, r_c_s2, r_c_e2;
    reg [REL_W-1:0]         r_pe;
    reg [1:0]               r_prev_spillover_mode;

    reg [PERIOD_WIDTH-1:0]  r_n_period;
    reg                     r_n_act_any, r_n_has_s2;
    reg [1:0]               r_n_mode1,   r_n_mode2;
    reg [REL_W-1:0]         r_n_s1, r_n_e1, r_n_s2, r_n_e2;

    wire vector_boundary_crossed = r_is_running && (r_ui_left <= DATA_WIDTH);

    // 下一向量相对本拍基址的偏移；ui_left<=64 时有效（跨边界 / next 掩码都只在此时使用）
    wire [SH_W:0]    ul7      = r_ui_left[SH_W:0];
    wire [OFF_W-1:0] n_off_s1 = {1'b0, r_n_s1} + ul7;
    wire [OFF_W-1:0] n_off_e1 = {1'b0, r_n_e1} + ul7;
    wire [OFF_W-1:0] n_off_s2 = {1'b0, r_n_s2} + ul7;
    wire [OFF_W-1:0] n_off_e2 = {1'b0, r_n_e2} + ul7;

    wire [REL_W-1:0] c_maxend     = r_c_has_s2 ? r_c_e2    : r_c_e1;
    wire [1:0]       c_spill_mode = r_c_has_s2 ? r_c_mode2 : r_c_mode1;

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
        end else begin
            r_n_period  <= in_period;
            r_n_act_any <= in_act_any; r_n_has_s2 <= in_has_s2;
            r_n_mode1   <= in_mode1;   r_n_mode2  <= in_mode2;
            r_n_s1 <= in_s1; r_n_e1 <= in_e1;
            r_n_s2 <= in_s2; r_n_e2 <= in_e2;

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
                // 新 period - 新 ptr = next_period + ui_left - 64
                r_ui_left             <= r_n_period + ul7 - DW_P;
                r_c_act_any <= r_n_act_any; r_c_has_s2 <= r_n_has_s2;
                r_c_mode1   <= r_n_mode1;   r_c_mode2  <= r_n_mode2;
                r_c_s1 <= sat_sub(n_off_s1); r_c_e1 <= sat_sub(n_off_e1);
                r_c_s2 <= sat_sub(n_off_s2); r_c_e2 <= sat_sub(n_off_e2);
                // spill - 新 ptr = max(max_end - ptr - 64, 0)，max_end<=period 时自然为 0
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

    reg r_data_valid, next_vector_req_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_data_valid        <= 1'b0;
            next_vector_req_reg <= 1'b0;
        end else begin
            next_vector_req_reg <= r_is_running && (trigger_sync || vector_boundary_crossed);
            r_data_valid        <= r_is_running;
        end
    end
    assign next_vector_req = next_vector_req_reg;

    // =========================================================================
    // 3. 掩码（只剩 比较常数 + 译码 + AND）
    // =========================================================================
    wire [DATA_WIDTH-1:0] next_vec_mask = (r_ui_left >= DATA_WIDTH) ? {DATA_WIDTH{1'b0}} :
                                          ~({DATA_WIDTH{1'b1}} << r_ui_left[SH_W-1:0]);

    wire [DATA_WIDTH-1:0] mask_c1   = r_c_act_any ? (thermo({1'b0, r_c_e1}) & ~thermo({1'b0, r_c_s1})) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_c2   = r_c_has_s2  ? (thermo({1'b0, r_c_e2}) & ~thermo({1'b0, r_c_s2})) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_n1   = r_n_act_any ? (thermo(n_off_e1) & ~thermo(n_off_s1)) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_n2   = r_n_has_s2  ? (thermo(n_off_e2) & ~thermo(n_off_s2)) : {DATA_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] mask_prev = thermo({1'b0, r_pe});

    // =========================================================================
    // 4. 并行比对展开与指令熔铸（与原版一致）
    // =========================================================================
    wire [DATA_WIDTH-1:0]   ui_win_mask_comb;
    wire [2*DATA_WIDTH-1:0] ui_op_code_comb;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_cmp_mask_bits
            wire is_next_vec = next_vec_mask[i];
            wire match_c2    = mask_c2[i];
            wire match_n2    = mask_n2[i];
            wire match_p     = mask_prev[i];
            wire match_curr  = mask_c1[i] | match_c2;
            wire match_next  = mask_n1[i] | match_n2;

            assign ui_win_mask_comb[i] = is_next_vec ? match_next : (match_curr | match_p);

            wire [1:0] op_curr = match_c2 ? r_c_mode2 : r_c_mode1;
            wire [1:0] op_next = match_n2 ? r_n_mode2 : r_n_mode1;
            assign ui_op_code_comb[2*i +: 2] = is_next_vec ? op_next :
                                               match_p     ? r_prev_spillover_mode : op_curr;
        end
    endgenerate

    // =========================================================================
    // 5. 打拍输出
    // =========================================================================
    reg [DATA_WIDTH-1:0]   r_cmp_win_mask;
    reg [2*DATA_WIDTH-1:0] r_cmp_op_code;

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
