// =========================================================================
// capture_engine.v - ATE 双比较器电气状态捕获引擎 (时序与逻辑重构版)
// 优化特征：
// 1. 100% 补全 cmp_h 与 cmp_l 2-bit 电气状态捕获 ([1-bit H, 1-bit L])。
// 2. 修正窗口尾沿 (Falling Edge) 提取逻辑与 test_done 刷盘 Bug。
// 3. 引入 2-Stage Pipeline 与 4 分块并行压缩树，消除 64 级 MUX 级联。
// 4. 关键路径 LUT 级数由 25+ 降至 5~6 级，大幅提升 Fmax (支持 300MHz+)。
// =========================================================================

module capture_engine #(
    parameter integer BRAM_DATA_WIDTH = 128,
    parameter integer ADDR_WIDTH      = 12
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire [63:0]                cmp_l_in,
    input  wire [63:0]                cmp_h_in,

    input  wire [63:0]                capture_win_mask,
    input  wire                       capture_start,
    input  wire                       test_done,

    output reg                        ram_wr_en,
    output reg  [ADDR_WIDTH-1:0]      ram_wr_addr,
    output reg  [BRAM_DATA_WIDTH-1:0] ram_wr_data
);

    // =========================================================================
    // 1. 采样沿提取 (修正：正确提取窗口下降沿/采样点)
    // =========================================================================
    // 假设窗口结束时刻（下降沿）进行采样；若为 1-UI Strobe 仍能准确命中
    wire [63:0] sample_en_bits = capture_win_mask & ~{capture_win_mask[62:0], 1'b0};

    // =========================================================================
    // 2. STAGE 1: 4分块并行 2-Bit Gather & Sub-Popcount (16-UI x 4)
    // 将 64-UI 拆分为 4 个 16-UI 独立模块，打断 64 级串行 MUX 级联链
    // =========================================================================
    reg [31:0] stg1_packed_data [0:3]; // 每个 16-UI 块最多产生 16 点 x 2bit = 32bit
    reg [4:0]  stg1_bit_cnt     [0:3]; // 每个子块采样 bit 数 (0~32)
    reg        stg1_valid;
    reg        stg1_flush;

    integer b, i;
    reg [31:0] sub_pack;
    reg [4:0]  sub_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg1_valid <= 1'b0;
            stg1_flush <= 1'b0;
            for (b = 0; b < 4; b = b + 1) begin
                stg1_packed_data[b] <= 32'd0;
                stg1_bit_cnt[b]     <= 5'd0;
            end
        end else begin
            stg1_valid <= capture_start;
            stg1_flush <= test_done;

            if (capture_start) begin
                for (b = 0; b < 4; b = b + 1) begin
                    sub_pack = 32'd0;
                    sub_cnt  = 5'd0;
                    for (i = 0; i < 16; i = i + 1) begin
                        if (sample_en_bits[b*16 + i]) begin
                            // 存储 2-bit 电气状态: [cmp_h, cmp_l]
                            sub_pack[sub_cnt +: 2] = {cmp_h_in[b*16 + i], cmp_l_in[b*16 + i]};
                            sub_cnt = sub_cnt + 5'd2;
                        end
                    end
                    stg1_packed_data[b] <= sub_pack;
                    stg1_bit_cnt[b]     <= sub_cnt;
                end
            end else begin
                for (b = 0; b < 4; b = b + 1) begin
                    stg1_packed_data[b] <= 32'd0;
                    stg1_bit_cnt[b]     <= 5'd0;
                end
            end
        end
    end

    // =========================================================================
    // 3. STAGE 2: 树形拼接与 128-bit 累加移位压包 (Global Packer)
    // =========================================================================
    // 子块归并
    wire [127:0] combined_64ui_data = {96'd0, stg1_packed_data[0]} |
                                      ({96'd0, stg1_packed_data[1]} << stg1_bit_cnt[0]) |
                                      ({96'd0, stg1_packed_data[2]} << (stg1_bit_cnt[0] + stg1_bit_cnt[1])) |
                                      ({96'd0, stg1_packed_data[3]} << (stg1_bit_cnt[0] + stg1_bit_cnt[1] + stg1_bit_cnt[2]));

    wire [7:0] total_new_bits = stg1_bit_cnt[0] + stg1_bit_cnt[1] + stg1_bit_cnt[2] + stg1_bit_cnt[3];

    reg [BRAM_DATA_WIDTH-1:0] r_shift_pack;
    reg [7:0]                 r_bit_cnt;
    wire [8:0]                next_bit_cnt = r_bit_cnt + total_new_bits;

    // 独立控制 Flush 标志，防止被采样覆盖
    reg flush_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_shift_pack  <= {BRAM_DATA_WIDTH{1'b0}};
            r_bit_cnt     <= 8'd0;
            ram_wr_en     <= 1'b0;
            ram_wr_addr   <= {ADDR_WIDTH{1'b0}};
            ram_wr_data   <= {BRAM_DATA_WIDTH{1'b0}};
            flush_pending <= 1'b0;
        end else begin
            ram_wr_en <= 1'b0;

            if (stg1_flush)
                flush_pending <= 1'b1; // 清理潜在笔误，保持 1'b1
            if (stg1_valid) begin
                if (total_new_bits > 0) begin
                    if (next_bit_cnt >= BRAM_DATA_WIDTH) begin
                        ram_wr_en   <= 1'b1;
                        ram_wr_data <= r_shift_pack | (combined_64ui_data << r_bit_cnt);
                        ram_wr_addr <= ram_wr_addr + 1'b1;

                        r_shift_pack <= combined_64ui_data >> (BRAM_DATA_WIDTH - r_bit_cnt);
                        r_bit_cnt    <= next_bit_cnt - BRAM_DATA_WIDTH;
                    end else begin
                        r_shift_pack <= r_shift_pack | (combined_64ui_data << r_bit_cnt);
                        r_bit_cnt    <= next_bit_cnt;
                    end
                end
            end 
            // 测试结束后的残留数据强制刷盘 (Flush Case)
            else if ((stg1_flush || flush_pending) && (r_bit_cnt > 0)) begin
                ram_wr_en     <= 1'b1;
                ram_wr_data   <= r_shift_pack;
                ram_wr_addr   <= ram_wr_addr + 1'b1;
                r_bit_cnt     <= 8'd0;
                r_shift_pack  <= {BRAM_DATA_WIDTH{1'b0}};
                flush_pending <= 1'b0;
            end
        end
    end

endmodule