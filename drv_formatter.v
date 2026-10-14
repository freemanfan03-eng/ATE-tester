// =========================================================================
// drv_formatter.v - 专职 DRV 驱动波形展开引擎 (双模完全解耦与 4 边沿优化版)
// =========================================================================
`include "wave_def.vh"

module drv_formatter #(
    parameter integer DATA_WIDTH   = 64,
    parameter integer EDGE_WIDTH   = 16,
    parameter integer PERIOD_WIDTH = 24
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // 流控接口
    input  wire                          trigger_sync,
    input  wire [PERIOD_WIDTH-1:0]      period_ui_in,

    // DRV 的 4 个驱动边沿时间戳 (E1 ~ E4)
    input  wire [EDGE_WIDTH-1:0]         act_edge_1_ui, act_edge_2_ui,
    input  wire [EDGE_WIDTH-1:0]         act_edge_3_ui, act_edge_4_ui,

    // DRV 的 4 个 1-bit 驱动目标电平
    input  wire                          act_e1, act_e2, act_e3, act_e4,

    // 输出接口
    output wire                          next_vector_req,
    output wire [DATA_WIDTH-1:0]        drv_parallel_data
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
    reg          r_prev_drv_small;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_small_phase    <= {PW{1'b0}};
            r_running_small  <= 1'b0;
            r_prev_drv_small <= 1'b0;
        end else if (trigger_sync) begin
            r_small_phase    <= {PW{1'b0}};
            r_running_small  <= 1'b1;
            r_prev_drv_small <= 1'b0;
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
    reg               r_prev_drv_large;
    reg               r_end_act;       
    reg [PW-1:0]      r_next_period;   
    reg [4:1]         r_curr_act;
    reg [4:1]         r_next_act;

    wire [EW-1:0]     edge_in [1:4];
    assign edge_in[1] = act_edge_1_ui;
    assign edge_in[2] = act_edge_2_ui;
    assign edge_in[3] = act_edge_3_ui;
    assign edge_in[4] = act_edge_4_ui;
    wire [4:1]        act_in = {act_e4, act_e3, act_e2, act_e1};

    wire [4:1]        vld_in;
    wire [4:1]        vld_nx;
    wire [DATA_WIDTH-1:0] mask_c [1:4];
    wire [DATA_WIDTH-1:0] mask_n [1:4];

    wire [PW-1:0] period_clamped = (period_safe < DW_P) ? DW_P : period_safe;

    wire [PW:0] ui_sum = {1'b0, r_ui_left} + (r_cross ? {1'b0, r_next_period} : {(PW+1){1'b0}});
    wire [PW:0] ui_dec = ui_sum - DW_PP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_running_large  <= 1'b0;
            r_cross          <= 1'b0;
            r_cross_part     <= 1'b0;
            r_ui_left        <= DW_P;
            r_prev_drv_large <= 1'b0;
        end else if (trigger_sync) begin
            r_running_large  <= 1'b1;
            r_ui_left        <= period_clamped;
            r_cross          <= (period_ui_in <= DW_P);
            r_cross_part     <= 1'b0;
            r_prev_drv_large <= 1'b0;
        end else if (r_running_large && !is_small_period) begin
            r_ui_left        <= ui_dec[PW-1:0];
            r_cross          <= (ui_sum <= DW2_PP);
            r_cross_part     <= (ui_sum <  DW2_PP);
            if (r_cross)
                r_prev_drv_large <= r_end_act;
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
    wire end_act_trig =
        vld_in[4] ? act_e4 :
        vld_in[3] ? act_e3 :
        vld_in[2] ? act_e2 :
        vld_in[1] ? act_e1 : 1'b0;

    wire end_act_cross =
        vld_nx[4] ? r_next_act[4] :
        vld_nx[3] ? r_next_act[3] :
        vld_nx[2] ? r_next_act[2] :
        vld_nx[1] ? r_next_act[1] : r_end_act;

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

    // 4 边沿打拍与掩码生成
    genvar k;
    generate
        for (k = 1; k <= 4; k = k + 1) begin : gen_edge
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
    // 3. 组合波形生成：双模隔离选择 (4 个边沿区间划分)
    // =========================================================================
    wire [DATA_WIDTH-1:0] ui_gt = thermo(1'b0, r_ui_left[SH-1:0]);
    wire [DATA_WIDTH-1:0] comb_drv_parallel;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_wave_bits
            // 小周期计算分量 (4 边沿划分 5 个相位区间)
            wire [PW-1:0] small_ui = (r_small_phase + i) % period_safe;
            wire s_e1 = (small_ui < act_edge_1_ui);
            wire s_e2 = (small_ui >= act_edge_1_ui) && (small_ui < act_edge_2_ui);
            wire s_e3 = (small_ui >= act_edge_2_ui) && (small_ui < act_edge_3_ui);
            wire s_e4 = (small_ui >= act_edge_3_ui) && (small_ui < act_edge_4_ui);
            wire small_bit = s_e1 ? r_prev_drv_small :
                             s_e2 ? act_e1          :
                             s_e3 ? act_e2          :
                             s_e4 ? act_e3          : act_e4;

            // 大周期计算分量 (双向量无缝跨界)
            wire is_next_vec = r_cross_part & ~ui_gt[i];
            wire curr_bit =
                mask_c[1][i] ? r_prev_drv_large :
                mask_c[2][i] ? r_curr_act[1]    :
                mask_c[3][i] ? r_curr_act[2]    :
                mask_c[4][i] ? r_curr_act[3]    : r_curr_act[4];

            wire next_bit =
                mask_n[1][i] ? r_end_act        :
                mask_n[2][i] ? r_next_act[1]    :
                mask_n[3][i] ? r_next_act[2]    :
                mask_n[4][i] ? r_next_act[3]    : r_next_act[4];

            wire large_bit = is_next_vec ? next_bit : curr_bit;

            assign comb_drv_parallel[i] = is_small_period ? small_bit : large_bit;
        end
    endgenerate

    // =========================================================================
    // 4. 最终打拍输出 (首窗口修复)
    // =========================================================================
    reg [DATA_WIDTH-1:0] r_drv_parallel;
    wire r_running_all = r_running_large || r_running_small;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_drv_parallel <= {DATA_WIDTH{1'b0}};
        end else if (!r_running_all) begin
            r_drv_parallel <= {DATA_WIDTH{1'b0}};
        end else begin
            r_drv_parallel <= comb_drv_parallel;
        end
    end

    assign drv_parallel_data = r_drv_parallel;

endmodule