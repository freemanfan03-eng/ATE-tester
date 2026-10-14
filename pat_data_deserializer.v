`timescale 1ns / 1ps

// =========================================================================
// pat_data_deserializer.v - 并转串 (仅行为级仿真模型, 不可综合)
// =========================================================================
// 修复记录:
//  [FIX1] start 原为下降沿检测 (~dly[1] & dly[2]), 比期望晚一个 clk,
//         首次装载取到的是窗口 1, 窗口 0 被跳过。现改为上升沿检测。
//  [FIX2] 边沿检测的延迟拍数由参数 DELAY_TAPS 配置 (默认 1, 与 FIX1 等价)。
//
// DELAY_TAPS 含义:
//   trigger_sync_dly[0] 为 trigger_sync 打 1 拍, [k] 为打 k+1 拍。
//   start = dly[DELAY_TAPS] & ~dly[DELAY_TAPS+1]
//   即 start 在 trigger_sync 被采样 (E1) 之后第 DELAY_TAPS+1 个 clk 沿
//   (E(DELAY_TAPS+1)) 到 E(DELAY_TAPS+2) 之间为 1, 宽度 1 个 clk。
//
// 时序 (E1 为采到 trigger_sync 的 clk 沿, 对接修复后的 *_formatter,
//       窗口 0 在 E2 之后出现在并行口上):
//   DELAY_TAPS = 1: start 在 E2~E3 之间为 1
//       E3 之后 r_current_vector = 窗口0
//       E3 后第 1 个快拍装载窗口 0                      <- 默认
//   formatter 输出延迟每增加 1 拍, DELAY_TAPS 同步加 1。
//
// 使用假设:
//  - trigger_sync 为 1 拍宽脉冲
//  - clk 周期 = DATA_WIDTH * 0.1 ns (DATA_WIDTH=64 时为 6.4 ns)
//  - clk 沿不应与 clk_100ps 上升沿重合 (否则装载拍会有竞争)
//  - r_bit_cnt 固定 6 位, DATA_WIDTH 不为 64 时需同步修改
//  - DELAY_TAPS >= 0
// =========================================================================
module pat_data_deserializer #(
    parameter integer DATA_WIDTH = 64,
    parameter integer DELAY_TAPS = 4     // 边沿检测前的延迟拍数
)(
    input  wire                  clk,               // 主系统时钟：每个 clk 周期更新一次 pat_parallel_data
    input  wire                  rst_n,             // 异步复位
    input  wire                  trigger_sync,
    input  wire [DATA_WIDTH-1:0] pat_parallel_data, // 每个 clk 周期送入的新并行数据
    output reg                   ser_out            // 1-bit 高速串行波形输出
);

    // 1. 锁存当前周期的并行数据：在每个 clk 的上升沿，把当拍的新数据安全锁存下来
    reg [DATA_WIDTH-1:0] r_current_vector;

    // 延迟链: 位 [DELAY_TAPS+1:0], 共 DELAY_TAPS+2 位
    //   dly[DELAY_TAPS]   : trigger_sync 延迟 DELAY_TAPS+1 拍
    //   dly[DELAY_TAPS+1] : 再延迟 1 拍, 用于上升沿检测
    reg [DELAY_TAPS+1:0] trigger_sync_dly;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_current_vector <= {DATA_WIDTH{1'b0}};
            trigger_sync_dly <= {(DELAY_TAPS+2){1'b0}};
        end else begin
            r_current_vector <= pat_parallel_data; // 以 clk 边沿作为每个数据周期的起点
            trigger_sync_dly <= {trigger_sync_dly[DELAY_TAPS:0], trigger_sync};
        end
    end

    // 上升沿检测: 延迟由 DELAY_TAPS 配置
    wire start = trigger_sync_dly[DELAY_TAPS] & ~trigger_sync_dly[DELAY_TAPS+1];

    // 2. 内部 100ps 高速移位逻辑 (必须与 clk 保持相位对齐或通过同步机制处理)
    reg [5:0]            r_bit_cnt;
    reg [DATA_WIDTH-1:0] r_shift_reg;
    reg                  clk_100ps;

    // 内部衍生 100ps 节拍 (仅作行为级仿真演示)
    localparam real STEP_NS = 0.1;
    initial clk_100ps = 0;
    always #(STEP_NS / 2.0) clk_100ps = ~clk_100ps;

    reg isruning;

    // 在高速节拍下移位, 在计数满时同步加载 r_current_vector
    always @(posedge clk_100ps or negedge rst_n) begin
        if (!rst_n) begin
            r_bit_cnt   <= 6'd0;
            r_shift_reg <= {DATA_WIDTH{1'b0}};
            ser_out     <= 1'b0;
            isruning    <= 1'b0;
        end else begin
            if (start & ~isruning) begin
                r_bit_cnt <= 6'd0;
                isruning  <= 1'b1;
            end
            if (isruning) begin
                // 计数满 DATA_WIDTH 步时载入 clk 域锁存好的并行数据
                if (r_bit_cnt == DATA_WIDTH - 1'd1) begin
                    r_bit_cnt   <= 6'd0;
                    r_shift_reg <= r_current_vector;
                    ser_out     <= r_current_vector[0];
                end else begin
                    r_bit_cnt   <= r_bit_cnt + 1'd1;
                    ser_out     <= r_shift_reg[1];
                    r_shift_reg <= {1'b0, r_shift_reg[DATA_WIDTH-1:1]};
                end
            end
        end
    end

endmodule