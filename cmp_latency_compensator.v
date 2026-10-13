// =========================================================================
// cmp_latency_compensator.v - 单通道确定性延时补偿器 (优化版)
//
// 时钟域: txusrclk2 (cmp_formatter / 本模块 / compare_engine 同域)
//
// 总延迟 = 64*(cfg_latency_cycles + 1) + cfg_latency_ui   (单位: UI)
//   - cfg_latency_cycles : 整拍补偿 (0 ~ MAX_DELAY_CYCLES-1)
//   - cfg_latency_ui     : UI 级补偿 (0 ~ DATA_WIDTH-1), bit0 为最早 UI
//   - "+1 拍" 是输出寄存器的固定延迟, 校准时自然吸收
//
// 相对旧版的改动:
//   1. 删除 expect_data: 预期值已由 op_code 表达, payload 256 -> 192 bit
//   2. 增加 UI 级桶形移位: 吸收 GT 字对齐 / 走线 / ADATE318 的非整拍延迟
//   3. cfg_latency_cycles = 0 时真正零拍 (旧版最小 1 拍)
//   4. 延迟线不带复位, 可推导 SRL; 用 fill 计数器 + link_ready 门控,
//      避免上电/复位后读到 X 或残留数据
//   5. emergency_stop / link_ready 先同步到本时钟域
//   6. 移位 + 选择结果打一拍输出, 改善时序
//
// 约定:
//   - bit[i] 对应第 i 个 UI, i 小 = 时间早 (须与 GT RX 解串顺序一致)
//   - cfg_latency_* 只在 link_ready=0 或测试空闲时修改
//   - MAX_DELAY_CYCLES >= 2
// =========================================================================

module cmp_latency_compensator #(
    parameter integer DATA_WIDTH       = 64,
    parameter integer MAX_DELAY_CYCLES = 64
)(
    input  wire                                 clk,              // txusrclk2
    input  wire                                 rst_n,

    // 校准 / 控制
    input  wire                                 link_ready,       // GT tx/rx reset_done 且对齐完成 (可异步, 内部同步)
    input  wire [$clog2(MAX_DELAY_CYCLES)-1:0]  cfg_latency_cycles,
    input  wire [$clog2(DATA_WIDTH)-1:0]        cfg_latency_ui,
    input  wire                                 emergency_stop,   // 可异步, 内部同步

    // 来自 cmp_formatter
    input  wire [DATA_WIDTH-1:0]                in_cmp_win_mask,
    input  wire [2*DATA_WIDTH-1:0]              in_cmp_op_code,

    // 送往 compare_engine
    output wire [DATA_WIDTH-1:0]                out_cmp_win_mask,
    output wire [2*DATA_WIDTH-1:0]              out_cmp_op_code
);

    localparam integer CW = $clog2(MAX_DELAY_CYCLES);
    localparam integer SW = $clog2(DATA_WIDTH);
    localparam integer PW = 3 * DATA_WIDTH;          // mask(1) + op(2) 每 UI 3 bit
    localparam [SW:0]  DW_C = DATA_WIDTH;

    // ---------------------------------------------------------------------
    // 0. 控制信号同步 (复位值取安全态: 屏蔽比对)
    // ---------------------------------------------------------------------
    reg [1:0] link_sync;
    reg [1:0] stop_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            link_sync <= 2'b00;
            stop_sync <= 2'b11;
        end else begin
            link_sync <= {link_sync[0], link_ready};
            stop_sync <= {stop_sync[0], emergency_stop};
        end
    end
    wire link_s = link_sync[1];
    wire stop_s = stop_sync[1];

    // ---------------------------------------------------------------------
    // 1. 打包 (mask 在高位, op 在低位)
    // ---------------------------------------------------------------------
    wire [PW-1:0] in_payload = {in_cmp_win_mask, in_cmp_op_code};

    // ---------------------------------------------------------------------
    // 2. 整拍延迟线 (无复位, 综合为 SRL; 深度 MAX-1, 抽头 k 对应 k 拍)
    // ---------------------------------------------------------------------
    (* shreg_extract = "yes" *)
    reg [PW-1:0] dl [0:MAX_DELAY_CYCLES-2];

    integer i;
    always @(posedge clk) begin
        dl[0] <= in_payload;
        for (i = 1; i < MAX_DELAY_CYCLES-1; i = i + 1)
            dl[i] <= dl[i-1];
    end

    wire [PW-1:0] w_cur = (cfg_latency_cycles == {CW{1'b0}}) ? in_payload
                                                             : dl[cfg_latency_cycles - 1'b1];

    // 上一拍的字级输出, 供 UI 级移位取高位 UI
    reg [PW-1:0] w_prev;
    always @(posedge clk) w_prev <= w_cur;

    // ---------------------------------------------------------------------
    // 3. 预热计数: link_ready 后经过 > cfg_latency_cycles 拍, 数据才有效
    //    (UI 移位还需要 w_prev 有效, 故用 ">" 而非 ">=")
    // ---------------------------------------------------------------------
    reg [CW:0] fill_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fill_cnt <= {(CW+1){1'b0}};
        else if (!link_s)
            fill_cnt <= {(CW+1){1'b0}};
        else if (fill_cnt != MAX_DELAY_CYCLES)
            fill_cnt <= fill_cnt + 1'b1;
    end
    wire warm = link_s && (fill_cnt > {1'b0, cfg_latency_cycles});

    // ---------------------------------------------------------------------
    // 4. UI 级桶形移位: out[j] = seq[j - k]
    //    seq = {当前字, 上一字}, 当前字 UI j 位于 DATA_WIDTH + j
    // ---------------------------------------------------------------------
    wire [DATA_WIDTH-1:0]   m_cur  = w_cur [PW-1 -: DATA_WIDTH];
    wire [2*DATA_WIDTH-1:0] o_cur  = w_cur [2*DATA_WIDTH-1:0];
    wire [DATA_WIDTH-1:0]   m_prev = w_prev[PW-1 -: DATA_WIDTH];
    wire [2*DATA_WIDTH-1:0] o_prev = w_prev[2*DATA_WIDTH-1:0];

    wire [SW:0] sh = DW_C - {1'b0, cfg_latency_ui};      // 1 ~ DATA_WIDTH

    wire [2*DATA_WIDTH-1:0] cat_m = {m_cur, m_prev};
    wire [4*DATA_WIDTH-1:0] cat_o = {o_cur, o_prev};
    wire [2*DATA_WIDTH-1:0] sh_m  = cat_m >> sh;
    wire [4*DATA_WIDTH-1:0] sh_o  = cat_o >> {sh, 1'b0}; // op 每 UI 2 bit

    // ---------------------------------------------------------------------
    // 5. 输出寄存 + 急停门禁
    //    mask 带复位并受 warm 门控; op 在 mask=0 时无意义, 不带复位
    // ---------------------------------------------------------------------
    reg [DATA_WIDTH-1:0]   r_mask;
    reg [2*DATA_WIDTH-1:0] r_op;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_mask <= {DATA_WIDTH{1'b0}};
        else
            r_mask <= warm ? sh_m[DATA_WIDTH-1:0] : {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk) r_op <= sh_o[2*DATA_WIDTH-1:0];

    assign out_cmp_win_mask = stop_s ? {DATA_WIDTH{1'b0}} : r_mask;
    assign out_cmp_op_code  = r_op;

endmodule