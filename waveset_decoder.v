// =========================================================================
// waveset_decoder_v2.v - WAVESET 查表与译码 (优化版, 端口向下兼容)
// =========================================================================
// 相对 v1 的改动:
//  [1] 内置表与自定义表统一为 32bit 字 {D0,D1,D2,D3,D4,D5,R0,R1}, 共用一套译码,
//      译码只写一份 (原来 LUT -> 译码 -> 覆写 三段, 且自定义字只用了低 32 位)。
//  [2] 自定义字扩展为 PAT_ACT_GROUNP 组: index 9 -> cfg[31:0], index 10 -> cfg[63:32] ...
//      (index 9 行为与旧版一致)。
//  [3] N(无动作) 语义修正为"保持":
//        act_e2~e4 = N 时继承前一边沿电平 (原版 N 被当成 0, 会把电平拉低);
//        act_e5    = N 时继承 e0。
//      另有内部信号 act_edge_en[5:0] (bit k: Ek 有动作), 暂未引出端口。
//  [4] 格式 1 (DNRZ) 原表为 {Z,_1,F,N,N,Z,...}: D0=Z 驱动永远关闭, D2 槽位放了 F
//      (译码器不识别), 实际波形是错的。这里按 {F,N,_1,N,N,Z} 修正。  ## 待确认 ##
//  [5] R1 的 C(关窗) 仅在 R0 为窗口指令时有效, 单独出现不再被当成 L 单点比对。
//  [6] debug 覆写: PATHI/PATLO 把 e1~e4 全部强制 (原版漏了 e2/e3, 电平会中途翻转)。
//  [7] 内部信号 act_illegal: 仅 SRC_PAT 下有效, 标记未定义 index / 槽位非法码 / 窗口开关不配对,
//      暂未引出端口。端口列表与 v1 完全一致, 可直接替换。
//
// 全部为组合逻辑。pattern_index 与 act_edge_*_ui 必须在同一拍对齐进入 formatter。
// =========================================================================
`include "wave_def.vh"

module waveset_decoder #(
    parameter integer PAT_ACT_GROUNP = 2        // 自定义字组数 (每组 32bit), 最大 7
)
(
    input  wire [3:0]                     pattern_index,
    input  wire [32*PAT_ACT_GROUNP-1:0]   pattern_act_cfg,
    input  wire [2:0]                     data_src_sel,

    // 驱动控制 (e0/e5: 0=Driver ON, 1=High-Z; e1~e4: 驱动电平)
    output reg        act_e0,
    output reg        act_e1,
    output reg        act_e2,
    output reg        act_e3,
    output reg        act_e4,
    output reg        act_e5,

    // 比对控制
    output reg        act_r0_en,
    output reg [1:0]  act_r0_mode,
    output reg        act_cmp_win_en,
    output reg        act_r1_en,
    output reg [1:0]  act_r1_mode
);

    // ---------------------------------------------------------------------
    // 内部信号 (暂不引出端口, 后续按需加端口; 仿真可用 dut.act_edge_en / dut.act_illegal 观察)
    // ---------------------------------------------------------------------
    reg [5:0] act_edge_en;      // bit k = Ek 有动作 (非 N)
    reg       act_illegal;      // 配置非法 (仅诊断, 不改变输出; 仅 SRC_PAT 下有效)

    // ---------------------------------------------------------------------
    // 符号别名 (显式 4bit, 避免 localparam 位宽歧义)
    // ---------------------------------------------------------------------
    localparam [3:0] N  = `ACT_N;
    localparam [3:0] _0 = `ACT_DRV_0;
    localparam [3:0] _1 = `ACT_DRV_1;
    localparam [3:0] Z  = `ACT_F_OFF;
    localparam [3:0] F  = `ACT_F_ON;
    localparam [3:0] L  = `ACT_CMP_L;
    localparam [3:0] H  = `ACT_CMP_H;
    localparam [3:0] V  = `ACT_CMP_V;
    localparam [3:0] M  = `ACT_CMP_M;
    localparam [3:0] wL = `ACT_WIN_L;
    localparam [3:0] wH = `ACT_WIN_H;
    localparam [3:0] wV = `ACT_WIN_V;
    localparam [3:0] wM = `ACT_WIN_M;
    localparam [3:0] C  = `ACT_CLOSE;

    localparam [3:0] CUST_BASE = 4'd9;

    // ---------------------------------------------------------------------
    // 1. 内置 WAVESET 表: {D0,D1,D2,D3,D4,D5,R0,R1}
    // ---------------------------------------------------------------------
    function [31:0] builtin_word;
        input [3:0] idx;
        begin
            case (idx)
                4'h0:    builtin_word = {F, _1, N,  N,  N,  Z, N,  N};  // NRZ
                4'h1:    builtin_word = {F, N,  _1, N,  N,  Z, N,  N};  // DNRZ  ## 待确认 ##
                4'h2:    builtin_word = {F, _1, _0, _1, _0, Z, H, H};  // RZ (窗口比对 L)
                4'h3:    builtin_word = {F, _0, _1, N,  N,  Z, N,  N};  // RO
                4'h4:    builtin_word = {F, _0, _1, _0, N,  Z, N,  N};  // SBC
                4'h5:    builtin_word = {Z, N,  N,  N,  N,  Z, N,  N};  // High-Z
                4'h6:    builtin_word = {Z, N,  N,  N,  N,  Z, H,  N};  // Edge Compare
                4'h7:    builtin_word = {Z, N,  N,  N,  N,  Z, wL, C};  // Window Compare
                default: builtin_word = 32'd0;                          // 全 N
            endcase
        end
    endfunction

    // 自定义字选择
    wire [3:0] cust_idx = pattern_index - CUST_BASE;
    wire       is_cust  = (pattern_index >= CUST_BASE) && (cust_idx < PAT_ACT_GROUNP);

    reg [31:0] cust_word;
    integer    g;
    always @(*) begin
        cust_word = 32'd0;
        for (g = 0; g < PAT_ACT_GROUNP; g = g + 1)
            if (cust_idx == g)
                cust_word = pattern_act_cfg[32*g +: 32];
    end

    wire        idx_ok = (pattern_index <= 4'h7) || is_cust;
    wire [31:0] word   = is_cust ? cust_word : builtin_word(pattern_index);

    wire [3:0] pat_e0 = word[31:28];
    wire [3:0] pat_e1 = word[27:24];
    wire [3:0] pat_e2 = word[23:20];
    wire [3:0] pat_e3 = word[19:16];
    wire [3:0] pat_e4 = word[15:12];
    wire [3:0] pat_e5 = word[11:8];
    wire [3:0] pat_r0 = word[7:4];
    wire [3:0] pat_r1 = word[3:0];

    // ---------------------------------------------------------------------
    // 2. 驱动侧译码 (N = 保持)
    // ---------------------------------------------------------------------
    wire en_e0 = (pat_e0 == F) | (pat_e0 == Z);
    wire en_e5 = (pat_e5 == F) | (pat_e5 == Z);
    wire en_e1 = (pat_e1 == _0) | (pat_e1 == _1);
    wire en_e2 = (pat_e2 == _0) | (pat_e2 == _1);
    wire en_e3 = (pat_e3 == _0) | (pat_e3 == _1);
    wire en_e4 = (pat_e4 == _0) | (pat_e4 == _1);

    wire lut_e0 = (pat_e0 == F) ? 1'b0 : 1'b1;                 // F=ON(0), 其余(Z/N)=High-Z(1)
    wire lut_e5 = en_e5 ? (pat_e5 == Z) : lut_e0;              // N 继承 e0
    wire lut_e1 = en_e1 ? (pat_e1 == _1) : 1'b0;
    wire lut_e2 = en_e2 ? (pat_e2 == _1) : lut_e1;
    wire lut_e3 = en_e3 ? (pat_e3 == _1) : lut_e2;
    wire lut_e4 = en_e4 ? (pat_e4 == _1) : lut_e3;

    // ---------------------------------------------------------------------
    // 3. 比对侧译码
    // ---------------------------------------------------------------------
    wire r0_strobe = (pat_r0 == L) | (pat_r0 == H) | (pat_r0 == M) | (pat_r0 == V);
    wire r0_win    = (pat_r0 == wL) | (pat_r0 == wH) | (pat_r0 == wM) | (pat_r0 == wV);
    wire r1_strobe = (pat_r1 == L) | (pat_r1 == H) | (pat_r1 == M) | (pat_r1 == V);
    wire r1_close  = (pat_r1 == C);

    reg [1:0] r0_mode_c, r1_mode_c;
    always @(*) begin
        case (pat_r0)
            H, wH:   r0_mode_c = 2'b01;
            M, wM:   r0_mode_c = 2'b10;
            V, wV:   r0_mode_c = 2'b11;
            default: r0_mode_c = 2'b00;      // L / wL / 其它
        endcase
        case (pat_r1)
            H:       r1_mode_c = 2'b01;
            M:       r1_mode_c = 2'b10;
            V:       r1_mode_c = 2'b11;
            default: r1_mode_c = 2'b00;      // L / C / 其它
        endcase
    end

    wire lut_r0_en = r0_strobe | r0_win;
    wire lut_r1_en = r1_strobe | (r1_close & r0_win);

    // ---------------------------------------------------------------------
    // 4. 合法性诊断
    // ---------------------------------------------------------------------
    wire bad_d0 = ~((pat_e0 == N) | en_e0);
    wire bad_d5 = ~((pat_e5 == N) | en_e5);
    wire bad_d1 = ~((pat_e1 == N) | en_e1);
    wire bad_d2 = ~((pat_e2 == N) | en_e2);
    wire bad_d3 = ~((pat_e3 == N) | en_e3);
    wire bad_d4 = ~((pat_e4 == N) | en_e4);
    wire bad_r0 = ~((pat_r0 == N) | r0_strobe | r0_win);
    wire bad_r1 = ~((pat_r1 == N) | r1_strobe | r1_close);
    wire bad_pair = (r0_win & ~r1_close) | (r1_close & ~r0_win);

    wire illegal_c = ~idx_ok | bad_d0 | bad_d1 | bad_d2 | bad_d3 | bad_d4 | bad_d5
                   | bad_r0 | bad_r1 | bad_pair;

    // ---------------------------------------------------------------------
    // 5. 输出 MUX + debug 覆写
    // ---------------------------------------------------------------------
    always @(*) begin
        act_e0         = lut_e0;
        act_e1         = lut_e1;
        act_e2         = lut_e2;
        act_e3         = lut_e3;
        act_e4         = lut_e4;
        act_e5         = lut_e5;
        act_r0_en      = lut_r0_en;
        act_r0_mode    = r0_mode_c;
        act_cmp_win_en = r0_win;
        act_r1_en      = lut_r1_en;
        act_r1_mode    = r1_strobe ? r1_mode_c : 2'b00;
        act_edge_en    = {en_e5, en_e4, en_e3, en_e2, en_e1, en_e0};
        act_illegal    = 1'b0;

        case (data_src_sel)
            `SRC_PAT: begin
                act_illegal = illegal_c;
            end
            `SRC_PATHI, `SRC_ALLHI: begin
                act_e0 = 1'b0; act_e5 = 1'b0;
                act_e1 = 1'b1; act_e2 = 1'b1; act_e3 = 1'b1; act_e4 = 1'b1;
                act_edge_en = 6'b111111;
            end
            `SRC_PATLO, `SRC_ALLLO: begin
                act_e0 = 1'b0; act_e5 = 1'b0;
                act_e1 = 1'b0; act_e2 = 1'b0; act_e3 = 1'b0; act_e4 = 1'b0;
                act_edge_en = 6'b111111;
            end
            default: begin                // SRC_TRIS 及未定义值: 驱动关闭
                act_e0 = 1'b1; act_e5 = 1'b1;
                act_edge_en = 6'b111111;
            end
        endcase
    end

endmodule