module edge_rule_checker #(
    parameter EDGE_WIDTH   = 16,     
    parameter PERIOD_WIDTH = 24      
)(
    input wire                    clk,
    input wire                    rst_n,
    input wire [PERIOD_WIDTH-1:0] period_in,
    input wire [EDGE_WIDTH-1:0]   edge_0,      
    input wire [EDGE_WIDTH-1:0]   edge_1,      
    input wire [EDGE_WIDTH-1:0]   edge_2,      
    input wire [EDGE_WIDTH-1:0]   edge_3,
    input wire [EDGE_WIDTH-1:0]   edge_4,      
    input wire [EDGE_WIDTH-1:0]   edge_5,      
    input wire [EDGE_WIDTH-1:0]   edge_r0,     
    input wire [EDGE_WIDTH-1:0]   edge_r1,
    
    // 错误标志输出（如果违背规则，对应标志拉高）
    output reg                    rule_violation
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rule_violation <= 1'b0;
        end else begin
            // 检查规则 1: D1 <= D2 <= D4 <= D5
            // 检查规则 2: D0 <= D3
            // 检查规则 3: R0 <= R1
            // 检查规则 4: 所有 8 个边沿值不能超过 waveform period (period_in)
            if ((edge_1 > edge_2) || (edge_2 > edge_4) || (edge_4 > edge_5) ||
                (edge_0 > edge_3) || 
                (edge_r0 > edge_r1) ||
                (edge_0 >= period_in) || (edge_1 >= period_in) || 
                (edge_2 >= period_in) || (edge_3 >= period_in) || 
                (edge_4 >= period_in) || (edge_5 >= period_in) || 
                (edge_r0 >= period_in) || (edge_r1 >= period_in)) begin
                
                rule_violation <= 1'b1;
            end else begin
                rule_violation <= 1'b0;
            end
        end
    end

    // 如果是在仿真中，也可以直接用 SystemVerilog Assertion (SVA) 打印报错
    `ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && rule_violation) begin
            $display("[ERROR] Time=%0t: WAVESET Timing Edge Rule Violation Detected!", $time);
            $display("Period=%0d | D0=%0d, D1=%0d, D2=%0d, D3=%0d, D4=%0d, D5=%0d, R0=%0d, R1=%0d", 
                     period_in, edge_0, edge_1, edge_2, edge_3, edge_4, edge_5, edge_r0, edge_r1);
        end
    end
    `endif

endmodule