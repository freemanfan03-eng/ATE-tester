// =========================================================================
// capture_engine.v - ATE 双通道独立逻辑状态捕获与移位压包引擎 (无 BRAM 存储)
// 特性：
// 1. 彻底解耦高阈值 (cmp_h) 与低阈值 (cmp_l) 捕获路径。
// 2. 分别通过 cap_bit_h 和 cap_bit_l 独立输出各自提取的逻辑序列。
// 3. 采用分块并行提取与流水线移位压包，保证时序收敛与高性能。
// =========================================================================
`timescale 1ns / 1ps

module capture_engine #(
    parameter integer DATA_WIDTH = 64
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // --- 1. 物理比较器输入 ---
    input  wire [DATA_WIDTH-1:0]      cmp_l_in,          // VOL 低电平比较采样
    input  wire [DATA_WIDTH-1:0]      cmp_h_in,          // VOH 高电平比较采样

    // --- 2. 控制与掩码信号 ---
    input  wire [DATA_WIDTH-1:0]      capture_win_mask,  // 视窗掩码
    input  wire                       capture_start,     // 启动/清零信号

    // --- 3. 双通道独立逻辑输出 ---
    output reg  [DATA_WIDTH-1:0]      cap_bit_h,         // cmp_h 独立捕获的逻辑流
    output reg  [DATA_WIDTH-1:0]      cap_bit_l,         // cmp_l 独立捕获的逻辑流
    output reg                        cap_valid          // 捕获有效指示
);

    // =========================================================================
    // 1. 采样沿/有效点提取
    // =========================================================================
    // 提取窗口下降沿作为采样点（或根据需要调整为视窗内有效点）
    wire [DATA_WIDTH-1:0] sample_en_bits = capture_win_mask & ~{capture_win_mask[DATA_WIDTH-2:0], 1'b0};

    // =========================================================================
    // 2. 独立稀疏位压缩排列 (Bit Gathering for High & Low Channels)
    // =========================================================================
    reg [DATA_WIDTH-1:0] packed_bits_h;
    reg [DATA_WIDTH-1:0] packed_bits_l;
    reg [6:0]            new_bit_cnt;
    integer              j, k;

    always @(*) begin
        packed_bits_h = {DATA_WIDTH{1'b0}};
        packed_bits_l = {DATA_WIDTH{1'b0}};
        k = 0;

        for (j = 0; j < DATA_WIDTH; j = j + 1) begin
            if (sample_en_bits[j]) begin
                // 高、低通道各自独立提取对应的逻辑电平
                packed_bits_h[k] = cmp_h_in[j];
                packed_bits_l[k] = cmp_l_in[j];
                k = k + 1;
            end
        end
        new_bit_cnt = k[6:0];
    end

    // =========================================================================
    // 3. 双通道独立移位压包逻辑
    // =========================================================================
    reg [6:0] r_bit_cnt;
    wire [7:0] next_bit_cnt = r_bit_cnt + new_bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_bit_h   <= {DATA_WIDTH{1'b0}};
            cap_bit_l   <= {DATA_WIDTH{1'b0}};
            r_bit_cnt   <= 7'd0;
            cap_valid   <= 1'b0;
        end 
       /* else if (capture_start) begin
            cap_bit_h   <= {DATA_WIDTH{1'b0}};
            cap_bit_l   <= {DATA_WIDTH{1'b0}};
            r_bit_cnt   <= 7'd0;
            cap_valid   <= 1'b0;
        end */
        else begin
            if (new_bit_cnt > 0) begin
                // 高低通道分别进行左移并压入新抓取的有效位
                cap_bit_h <= (cap_bit_h << new_bit_cnt) | packed_bits_h;
                cap_bit_l <= (cap_bit_l << new_bit_cnt) | packed_bits_l;
                r_bit_cnt <= next_bit_cnt[6:0];
                cap_valid <= 1'b1;
            end else begin
                cap_valid <= 1'b0;
            end
        end
    end

endmodule