// =========================================================================
// rcv_formatter.v - RCV 接收波形展开引擎 (语法修正版)
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
    input  wire [PERIOD_WIDTH-1:0]      period_ui_in,

    // RCV 专属的 2 个边沿 (E0, E5)
    input  wire [EDGE_WIDTH-1:0]         act_edge_0_ui,
    input  wire [EDGE_WIDTH-1:0]         act_edge_5_ui,
    input  wire                          act_e0,
    input  wire                          act_e5,

    output wire                          next_vector_req,
    output wire [DATA_WIDTH-1:0]        rcv_parallel_data
);

    // =========================================================================
    // 0. 常量与分层温度计译码定义
    // =========================================================================
    localparam integer SH = (DATA_WIDTH > 1) ? $clog2(DATA_WIDTH) : 1;
    localparam integer LW = SH / 2;
    localparam integer HW = SH - LW;
    localparam integer EW = EDGE_WIDTH;
    localparam integer PW = PERIOD_WIDTH;

    localparam [PW-1:0] DW_P   = DATA_WIDTH;
    localparam [PW:0]   DW_PP  = DATA_WIDTH;
    localparam [PW:0]   DW2_PP = 2 * DATA_WIDTH;
    localparam [EW:0]   DW_E   = DATA_WIDTH;
    localparam [EW:0]   DW2_E  = 2 * DATA_WIDTH;

    function automatic [DATA_WIDTH-1:0] thermo;
        input               sat;
        input [SH-1:0]      v;
        integer             j;
        reg [HW-1:0]        vh, a;
        reg [LW-1:0]        vl, b;
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

    // 模式自动判定
    wire is_small_period = (period_ui_in < DW_P);
    wire [PW-1:0] period_safe = (period_ui_in == 0) ? 1'd1 : period_ui_in;

    // =========================================================================
    // 1. 小周期专用：滚动相位累加器 (仅当 period_ui_in < 64 时工作)
    // =========================================================================
    reg [PW-1:0] r_small_phase;
    reg          r_running_small;
    reg          r_prev_rcv_small;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_small_phase    <= {PW{1'b0}};
            r_running_small  <= 1'b0;
            r_prev_rcv_small <= 1'b0;
        end else if (trigger_sync) begin
            r_small_phase    <= {PW{1'b0}};
            r_running_small  <= 1'b1;
            r_prev_rcv_small <= 1'b0;
        end else if (r_running_small && is_small_period) begin
            r_small_phase <= (r_small_phase + DATA_WIDTH) % period_safe;
        end else if (!is_small_period) begin
            r_running_small <= 1'b0;
        end
    end

    // =========================================================================
    // 2. 大周期专用：经典双向量无缝跨界状态机 (仅当 period_ui_in >= 64 时工作)
    // =========================================================================
    reg               r_running_large;
    reg               r_cross;         
    reg               r_cross_part;    
    reg [PW-1:0]      r_ui_left;       
    reg               r_prev_rcv_large;
    reg               r_end_act;       
    reg [PW-1:0]      r_next_period;   
    reg [1:0]         r_curr_act;
    reg [1:0]         r_next_act;

    wire [EW-1:0]     edge_in [0:1];
    assign edge_in[0] = act_edge_0_ui;
    assign edge_in[1] = act_edge_5_ui;
    wire [1:0]        act_in = {act_e5, act_e0};

    wire [1:0]        vld_in;
    wire [1:0]        vld_nx;
    wire [DATA_WIDTH-1:0] mask_c [0:1];
    wire [DATA_WIDTH-1:0] mask_n [0:1];

    wire [PW-1:0] period_clamped = (period_safe < DW_P) ? DW_P : period_safe;

    wire [PW:0] ui_sum = {1'b0, r_ui_left} + (r_cross ? {1'b0, r_next_period} : {(PW+1){1'b0}});
    wire [PW:0] ui_dec = ui_sum - DW_PP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_running_large  <= 1'b0;
            r_cross          <= 1'b0;
            r_cross_part     <= 1'b0;
            r_ui_left        <= DW_P;
            r_prev_rcv_large <= 1'b0;
        end else if (trigger_sync) begin
            r_running_large  <= 1'b1;
            r_ui_left        <= period_clamped;
            r_cross          <= (period_ui_in <= DW_P);
            r_cross_part     <= 1'b0;
            r_prev_rcv_large <= 1'b0;
        end else if (r_running_large && !is_small_period) begin
            r_ui_left        <= ui_dec[PW-1:0];
            r_cross          <= (ui_sum <= DW2_PP);
            r_cross_part     <= (ui_sum <  DW2_PP);
            if (r_cross)
                r_prev_rcv_large <= r_end_act;
        end else if (is_small_period) begin
            r_running_large <= 1'b0;
        end
    end

    // 握手逻辑
    reg next_vector_req_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_vector_req_reg <= 1'b0;
        end else begin
            next_vector_req_reg <= ((r_running_large || r_running_small) & trigger_sync) | r_cross;
        end
    end
    assign next_vector_req = next_vector_req_reg;

    // 数据通路影子寄存器
    wire end_act_trig  = vld_in[1] ? act_e5 : (vld_in[0] ? act_e0 : 1'b0);
    wire end_act_cross = vld_nx[1] ? r_next_act[1] : (vld_nx[0] ? r_next_act[0] : r_end_act);

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

    // 边沿打拍与掩码生成
    genvar k;
    generate
        for (k = 0; k < 2; k = k + 1) begin : gen_edge
            wire       esat_in = (edge_in[k] >= DW_E);
            reg [EW-1:0] r_nedge;
            reg        r_nesat;
            reg        r_nvld;

            assign vld_in[k] = (edge_in[k] < period_safe) | ~esat_in;
            assign vld_nx[k] = r_nvld;

            always @(posedge clk) begin
                r_nedge <= edge_in[k];
                r_nesat <= esat_in;
                r_nvld  <= vld_in[k];
            end

            reg [EW-1:0] r_rel;
            reg          r_sat;

            wire [EW:0] sum_n  = {1'b0, r_nedge} + {{(EW-SH){1'b0}}, r_ui_left[SH:0]};
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

            assign mask_c[k] = thermo(r_sat, r_rel[SH-1:0]);

            wire [SH:0] nsum = {1'b0, r_nedge[SH-1:0]} + {1'b0, r_ui_left[SH-1:0]};
            assign mask_n[k] = thermo(r_nesat | nsum[SH], nsum[SH-1:0]);
        end
    endgenerate

    // =========================================================================
    // 3. 组合波形生成：双模隔离选择
    // =========================================================================
    wire [DATA_WIDTH-1:0] ui_gt = thermo(1'b0, r_ui_left[SH-1:0]);
    wire [DATA_WIDTH-1:0] comb_rcv_parallel;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_wave_bits
            // 小周期计算分量
            wire [PW-1:0] small_ui = (r_small_phase + i) % period_safe;
            wire s_e0 = (small_ui < act_edge_0_ui);
            wire s_e5 = (small_ui >= act_edge_0_ui) && (small_ui < act_edge_5_ui);
            wire small_bit = s_e0 ? r_prev_rcv_small : (s_e5 ? act_e0 : act_e5);

            // 大周期计算分量
            wire is_next_vec = r_cross_part & ~ui_gt[i];
            wire curr_bit = mask_c[0][i] ? r_prev_rcv_large : (mask_c[1][i] ? r_curr_act[0] : r_curr_act[1]);
            wire next_bit = mask_n[0][i] ? r_end_act        : (mask_n[1][i] ? r_next_act[0] : r_next_act[1]);
            wire large_bit = is_next_vec ? next_bit : curr_bit;

            assign comb_rcv_parallel[i] = is_small_period ? small_bit : large_bit;
        end
    endgenerate

    // =========================================================================
    // 4. 最终打拍输出 (首窗口修复)
    // =========================================================================
    reg [DATA_WIDTH-1:0] r_rcv_parallel;
    wire r_running_all = r_running_large || r_running_small;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_rcv_parallel <= {DATA_WIDTH{1'b0}};
        end else if (!r_running_all) begin
            r_rcv_parallel <= {DATA_WIDTH{1'b0}};
        end else begin
            r_rcv_parallel <= comb_rcv_parallel;
        end
    end

    assign rcv_parallel_data = r_rcv_parallel;

endmodule