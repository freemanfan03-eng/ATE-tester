// =========================================================================
// 模块名称: gt_tmu_meas_engine
// 功能描述: 基于 drv_parallel_data 包络驱动的精简型 ATE TMU 测量引擎
// 变更说明: 控制窗口由 drv_parallel_data (1=使能窗口) 驱动，提取 start/stop 与 cnt
// =========================================================================

module gt_tmu_meas_engine #(
    parameter integer DATA_WIDTH = 64,  // 单拍并行 UI 宽度
    parameter integer IDX_WIDTH  = 6,   // 并行索引位宽 (2^6 = 64)
    parameter integer TS_WIDTH   = 40,  // 时间戳计数位宽
    parameter integer CYC_WIDTH  = 32   // 周期计数位宽
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // 1. 控制接口
    input  wire                   start_meas,          // 启动测量触发

    // 2. 联合逻辑输入 (DRV 驱动控制包络流 + DUT 比对数据流)
    input  wire [DATA_WIDTH-1:0]  drv_parallel_data,   // 驱动控制包络 (1=窗口内, 0=窗口外)
    input  wire [DATA_WIDTH-1:0]  cmp_l_in,            // 低阈值采样流 (用于周期/频率/上升沿)
    input  wire [DATA_WIDTH-1:0]  cmp_h_in,            // 高阈值采样流 (用于脉宽/下降沿)

    // 3. 硬件原生原子数据输出
    output reg  [TS_WIDTH-1:0]    high_pulse_ui_count, // 首脉冲高电平 UI 宽度
    output reg  [TS_WIDTH-1:0]    total_ui_count,      // start 到 stop 跨越的总 UI 跨度
    output reg  [CYC_WIDTH-1:0]   actual_cycles,       // 窗口内实际锁定的周期个数 cnt

    // 4. 状态标志输出
    output reg                    meas_busy,
    output reg                    meas_done
);

    // =========================================================================
    // 1. 跨拍打拍寄存器 (提取跨拍边沿)
    // =========================================================================
    reg r_drv_last_bit;
    reg r_cmp_l_last_bit;
    reg r_cmp_h_last_bit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_drv_last_bit   <= 1'b0;
            r_cmp_l_last_bit <= 1'b0;
            r_cmp_h_last_bit <= 1'b0;
        end else begin
            r_drv_last_bit   <= drv_parallel_data[DATA_WIDTH-1];
            r_cmp_l_last_bit <= cmp_l_in[DATA_WIDTH-1];
            r_cmp_h_last_bit <= cmp_h_in[DATA_WIDTH-1];
        end
    end

    // =========================================================================
    // 2. 联合逻辑运算：提取 start/stop 沿与被测信号跳变沿
    // =========================================================================
    wire [DATA_WIDTH-1:0] drv_rise;   // drv_parallel_data 0->1 (窗口开启 / start)
    wire [DATA_WIDTH-1:0] drv_fall;   // drv_parallel_data 1->0 (窗口关闭 / stop)
    wire [DATA_WIDTH-1:0] cmp_l_rise; // DUT 低阈值上升沿 (L->H)
    wire [DATA_WIDTH-1:0] cmp_h_fall; // DUT 高阈值下降沿 (H->L)

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_edge_det
            if (i == 0) begin
                assign drv_rise[0]   =  drv_parallel_data[0] && !r_drv_last_bit;
                assign drv_fall[0]   = !drv_parallel_data[0] &&  r_drv_last_bit;
                assign cmp_l_rise[0] =  cmp_l_in[0]          && !r_cmp_l_last_bit;
                assign cmp_h_fall[0] = !cmp_h_in[0]          &&  r_cmp_h_last_bit;
            end else begin
                assign drv_rise[i]   =  drv_parallel_data[i] && !drv_parallel_data[i-1];
                assign drv_fall[i]   = !drv_parallel_data[i] &&  drv_parallel_data[i-1];
                assign cmp_l_rise[i] =  cmp_l_in[i]          && !cmp_l_in[i-1];
                assign cmp_h_fall[i] = !cmp_h_in[i]          &&  cmp_h_in[i-1];
            end
        end
    endgenerate

    // 掩码过滤：仅当 drv_parallel_data == 1 时，被测边沿才视为有效
    wire [DATA_WIDTH-1:0] active_l_rises = cmp_l_rise & drv_parallel_data;
    wire [DATA_WIDTH-1:0] active_h_falls = cmp_h_fall & drv_parallel_data;

    // 统计单拍内的边沿总数 (cnt 累加)
    function [6:0] count_ones64(input [63:0] vec);
        integer k;
        begin
            count_ones64 = 7'd0;
            for (k = 0; k < 64; k = k + 1) begin
                if (vec[k]) count_ones64 = count_ones64 + 1'b1;
            end
        end
    endfunction

    // 树状优先级编码器：定位首个边沿位置
    function [2:0] enc8(input [7:0] d);
        casex (d)
            8'b1???????: enc8 = 3'd7;
            8'b01??????: enc8 = 3'd6;
            8'b001?????: enc8 = 3'd5;
            8'b0001????: enc8 = 3'd4;
            8'b00001???: enc8 = 3'd3;
            8'b000001??: enc8 = 3'd2;
            8'b0000001?: enc8 = 3'd1;
            8'b00000001: enc8 = 3'd0;
            default:     enc8 = 3'd0;
        endcase
    endfunction

    function [5:0] get_first_bit_index(input [63:0] d);
        if      (d[63:56] != 0) get_first_bit_index = {3'd7, enc8(d[63:56])};
        else if (d[55:48] != 0) get_first_bit_index = {3'd6, enc8(d[55:48])};
        else if (d[47:40] != 0) get_first_bit_index = {3'd5, enc8(d[47:40])};
        else if (d[39:32] != 0) get_first_bit_index = {3'd4, enc8(d[39:32])};
        else if (d[31:24] != 0) get_first_bit_index = {3'd3, enc8(d[31:24])};
        else if (d[23:16] != 0) get_first_bit_index = {3'd2, enc8(d[23:16])};
        else if (d[15:8]  != 0) get_first_bit_index = {3'd1, enc8(d[15:8])};
        else                    get_first_bit_index = {3'd0, enc8(d[7:0])};
    endfunction

    wire [IDX_WIDTH-1:0] start_win_idx = get_first_bit_index(drv_rise);
    wire [IDX_WIDTH-1:0] stop_win_idx  = get_first_bit_index(drv_fall);
    wire [IDX_WIDTH-1:0] l_rise_idx    = get_first_bit_index(active_l_rises);
    wire [IDX_WIDTH-1:0] h_fall_idx    = get_first_bit_index(active_h_falls);

    // =========================================================================
    // 3. 核心测量状态机
    // =========================================================================
    localparam IDLE      = 2'b00;
    localparam MEASURING = 2'b01;
    localparam DONE      = 2'b10;

    reg [1:0]          state;
    reg [TS_WIDTH-1:0] global_ui_counter;
    reg [TS_WIDTH-1:0] start_ui_ts;
    reg [TS_WIDTH-1:0] first_rise_ts;
    reg                win_active;
    reg                first_rise_got;
    reg                pulse_width_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            global_ui_counter   <= {TS_WIDTH{1'b0}};
            start_ui_ts         <= {TS_WIDTH{1'b0}};
            first_rise_ts       <= {TS_WIDTH{1'b0}};
            high_pulse_ui_count <= {TS_WIDTH{1'b0}};
            total_ui_count      <= {TS_WIDTH{1'b0}};
            actual_cycles       <= {CYC_WIDTH{1'b0}};
            win_active          <= 1'b0;
			
            first_rise_got      <= 1'b0;
            pulse_width_done    <= 1'b0;
            meas_busy           <= 1'b0;
            meas_done           <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    meas_done <= 1'b0;
                    if (start_meas) begin
                        state               <= MEASURING;
                        global_ui_counter   <= {TS_WIDTH{1'b0}};
                        actual_cycles       <= {CYC_WIDTH{1'b0}};
                        high_pulse_ui_count <= {TS_WIDTH{1'b0}};
                        total_ui_count      <= {TS_WIDTH{1'b0}};
                        win_active          <= 1'b0;
                        first_rise_got      <= 1'b0;
                        pulse_width_done    <= 1'b0;
                        meas_busy           <= 1'b1;
                    end
                end

                MEASURING: begin
                   global_ui_counter <= global_ui_counter + DATA_WIDTH;

                    // 【联合逻辑 A: START】drv_parallel_data 0->1 标记窗口使能开启
                    if (!win_active && |drv_rise) begin
                        start_ui_ts <= global_ui_counter + start_win_idx;
                        win_active  <= 1'b1;
                    end

                    // 【联合逻辑 B: 首沿捕获与脉宽测量】
                    if (win_active || (|drv_rise)) begin
                        // 1. 抓取首个 L 上升沿
                        if (!first_rise_got && |active_l_rises) begin
                            first_rise_ts  <= global_ui_counter + l_rise_idx;
                            first_rise_got <= 1'b1;
                        end

                        // 2. 抓取与首沿匹配的 H 下降沿，得出【脉宽 UI 计数】
                        if (first_rise_got && !pulse_width_done && |active_h_falls) begin
                            high_pulse_ui_count <= (global_ui_counter + h_fall_idx) - first_rise_ts;
                            pulse_width_done    <= 1'b1;
                        end

                        // 【联合逻辑 C: CNT 周期计数值】对窗口内出现的 L 上升沿求和
                        actual_cycles <= actual_cycles + count_ones64(active_l_rises);
                    end

                    // 【联合逻辑 D: STOP】drv_parallel_data 1->0 标记窗口关闭，锁定【总 UI 跨度】
                    if (win_active && |drv_fall) begin
                        total_ui_count <= (global_ui_counter + stop_win_idx) - start_ui_ts;
                        win_active     <= 1'b0;
                        meas_busy      <= 1'b0;
                        meas_done      <= 1'b1;
                        state          <= DONE;
                    end
                end

                DONE: begin
                    if (start_meas) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule