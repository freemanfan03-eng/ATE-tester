module edge_generator_8edge #(
    parameter EDGE_WIDTH   = 16,     
    parameter PERIOD_WIDTH = 24      
)(
    input wire                    clk,
    input wire                    rst_n,
    input wire                    trigger_sync,         // 全局同步/启动触发信号
    
    input wire [PERIOD_WIDTH-1:0] period_in,
    input wire [EDGE_WIDTH-1:0]   edge_0,      
    input wire [EDGE_WIDTH-1:0]   edge_1,      
    input wire [EDGE_WIDTH-1:0]   edge_2,      
    input wire [EDGE_WIDTH-1:0]   edge_3,
    input wire [EDGE_WIDTH-1:0]   edge_4,      // D4 的边沿输入
    input wire [EDGE_WIDTH-1:0]   edge_5,      // D5 的边沿输入
    input wire [EDGE_WIDTH-1:0]   edge_r0,     
    input wire [EDGE_WIDTH-1:0]   edge_r1,     
    
    output wire                   pulse_e0,
    output wire                   pulse_e1,
    output wire                   pulse_e2,
    output wire                   pulse_e3,
    output wire                   pulse_e4,     // D4 的边沿脉冲输出
    output wire                   pulse_e5,     // D5 的边沿脉冲输出
    output wire                   pulse_r0,
    output wire                   pulse_r1,
    output wire                   period_end   
);

    reg [PERIOD_WIDTH-1:0] down_counter;
    reg                    is_running;    // 运行状态标志，防止触发前空跑
    reg                    period_end_reg;

    // 主计数器与状态机控制
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            down_counter   <= {PERIOD_WIDTH{1'b0}};
            is_running     <= 1'b0;
            period_end_reg <= 1'b0;
        end else if (trigger_sync) begin
            // 收到 trigger_sync 瞬间：进入运行态，计数器归零
            is_running     <= 1'b1;
            down_counter   <= {PERIOD_WIDTH{1'b0}};
            period_end_reg <= 1'b0;
        end else if (!is_running) begin
            // 未启动前严格保持静止
            down_counter   <= {PERIOD_WIDTH{1'b0}};
            period_end_reg <= 1'b0;
        end else begin
            // 正常运行态下的高精度周期循环计数（允许数到等于 period_in 满量程）
            if (down_counter >= period_in-1) begin
                down_counter <= {PERIOD_WIDTH{1'b0}};
            end else begin
                down_counter <= down_counter + 1'b1;
            end

            // 周期结束前兆信号（在到达满量程前一拍拉高，带防下溢保护）
            if ((period_in > 1) && (down_counter == period_in - 1'd1)) begin
                period_end_reg <= 1'b1;
            end else begin
                period_end_reg <= 1'b0;
            end
        end
    end

    assign period_end = period_end_reg;

    // 组合逻辑生成高精度边沿脉冲（包含 e0 ~ e5 和 r0 ~ r1）：
    assign pulse_e0 = is_running && (down_counter == edge_0); //  D0
    assign pulse_e1 = is_running && (down_counter == edge_1); //  D1
    assign pulse_e2 = is_running && (down_counter == edge_2); //  D2
    
    assign pulse_e3 = is_running && (down_counter == edge_3); //  D3 (支持 100 满周期边界)
    assign pulse_e4 = is_running && (down_counter == edge_4); //  D4
    assign pulse_e5 = is_running && (down_counter == edge_5); //  D5
    
    // 采样/比较边沿保持原样
    assign pulse_r0 = is_running && (down_counter == edge_r0);
    assign pulse_r1 = is_running && (down_counter == edge_r1);

    // 规则检查器例化保持原样
    edge_rule_checker #(
        .EDGE_WIDTH   (EDGE_WIDTH),     
        .PERIOD_WIDTH (PERIOD_WIDTH)      
    ) edge_rule_checker_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .period_in       (period_in),
        .edge_0          (edge_0),
        .edge_1          (edge_1),
        .edge_2          (edge_2),
        .edge_3          (edge_3),
        .edge_4          (edge_4),
        .edge_5          (edge_5),
        .edge_r0         (edge_r0),
        .edge_r1         (edge_r1),
        .rule_violation  ()
    );

endmodule