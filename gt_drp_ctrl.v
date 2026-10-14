// =============================================================================
// File Name   : gt_drp_rom_ctrl.v
// Module Name : gt_drp_rom_ctrl
// Description : 通用基于查表法(ROM)的 Xilinx GT DRP 多寄存器连续读改写控制器
// Target HW   : 7-Series (GTX/GTP) / UltraScale (GTH/GTY)
// =============================================================================

module gt_drp_rom_ctrl #(
    parameter DRP_ADDR_WIDTH = 9,    // 7-Series 为 9, UltraScale 为 10
    parameter DRP_DATA_WIDTH = 16,   // DRP 数据位宽固定为 16
    parameter ROM_DEPTH      = 8     // 连续配置的寄存器最大条数
)(
    input  wire                      clk,            // DRP 管理时钟 (Free-running clk)
    input  wire                      rst,            // 高电平复位
    
    // 用户控制/状态接口
    input  wire                      start_cfg,      // 触发配置开始脉冲 (单周期高)
    input  wire [1:0]                cfg_mode,       // 模式选择 (如 0: 1.25G, 1: 10G)，决定加载哪一组 ROM
    output reg                       busy,           // 模块忙信号
    output reg                       done,           // 配置及复位完成脉冲
    
    // DRP 硬件接口 (直接连接至 GT DRP 端口)
    output reg  [DRP_ADDR_WIDTH-1:0] drp_addr,       // DRP 地址
    output reg                       drp_en,         // DRP 使能
    output reg                       drp_we,         // DRP 写使能
    output reg  [DRP_DATA_WIDTH-1:0] drp_di,         // DRP 写入数据
    input  wire [DRP_DATA_WIDTH-1:0] drp_do,         // DRP 读出数据
    input  wire                      drp_rdy,        // DRP 握手完成信号
    
    // GT 复位与状态握手接口
    output reg                       gt_soft_rst,    // 发给 GT 的软复位脉冲
    input  wire                      gt_txresetdone, // GT 发送端复位完成标志
    input  wire                      gt_rxresetdone  // GT 接收端复位完成标志
);

    // =========================================================================
    // 1. 定义 DRP 配置条目 (Address + Mask + Data)
    // =========================================================================
    // 结构：[DRP_ADDR_WIDTH-1 : 0] Address | [15 : 0] Mask | [15 : 0] Value
    localparam ENTRY_WIDTH = DRP_ADDR_WIDTH + 16 + 16;

    reg [$clog2(ROM_DEPTH)-1:0] rom_addr;
    reg [ENTRY_WIDTH-1:0]       rom_data;
    reg [$clog2(ROM_DEPTH)-1:0] total_entries;

    // 解析当前 ROM 数据的域
    wire [DRP_ADDR_WIDTH-1:0] current_drp_addr = rom_data[ENTRY_WIDTH-1 : 32];
    wire [15:0]               current_mask     = rom_data[31 : 16];
    wire [15:0]               current_val      = rom_data[15 : 0];

    // =========================================================================
    // 2. 配置 ROM 表定义 (可按需自行扩展)
    // =========================================================================
    always @(*) begin
        case (cfg_mode)
            // -----------------------------------------------------------------
            // Mode 0: 实例 (例如 切换到 1.25 Gbps)
            // -----------------------------------------------------------------
            2'b00: begin
                total_entries = 3; // 共 3 组寄存器
                case (rom_addr)
                    // 格式: {地址, 清零掩码(MASK), 目标写入值}
                    // 1) 0x088 (OUT_DIV): TXOUT_DIV/RXOUT_DIV 设为 /8 (3'b011)
                    0: rom_data = {9'h088, 16'h0077, 16'h0033}; 
                    // 2) 0x011 (DATA_WIDTH): RX/TX 位宽设为 16-bit (3'b011)
                    1: rom_data = {9'h011, 16'h3838, 16'h1818}; 
                    // 3) 0x0A8 (RXCDR_CFG_0): 调整 CDR 环路参数
                    2: rom_data = {9'h0A8, 16'hFFFF, 16'h0011}; 
                    default: rom_data = { {DRP_ADDR_WIDTH{1'b0}}, 32'd0 };
                endcase
            end

            // -----------------------------------------------------------------
            // Mode 1: 实例 (例如 切换到 10.3125 Gbps)
            // -----------------------------------------------------------------
            2'b01: begin
                total_entries = 3;
                case (rom_addr)
                    // 1) 0x088 (OUT_DIV): TXOUT_DIV/RXOUT_DIV 设为 /1 (3'b000)
                    0: rom_data = {9'h088, 16'h0077, 16'h0000}; 
                    // 2) 0x011 (DATA_WIDTH): RX/TX 位宽设为 32-bit (3'b110)
                    1: rom_data = {9'h011, 16'h3838, 16'h3030}; 
                    // 3) 0x0A8 (RXCDR_CFG_0): 10G 恢复时钟 CDR 环路参数
                    2: rom_data = {9'h0A8, 16'hFFFF, 16'h0020}; 
                    default: rom_data = { {DRP_ADDR_WIDTH{1'b0}}, 32'd0 };
                endcase
            end
			// -----------------------------------------------------------------
			// Mode : 5.0 Gbps 配置表
			// -----------------------------------------------------------------
			//    0x088 (OUT_DIV): 
			//    TXOUT_DIV (Bit[6:4]) = 3'b001 (/2 分频)
			//    RXOUT_DIV (Bit[2:0]) = 3'b001 (/2 分频)
			//    ROM 格式: {地址 (9-bit), 清零掩码 (16-bit), 目标值 (16-bit)}
	
			 2'b11: begin
                total_entries = 3;
                case (rom_addr)
                    // 1) 0x088 (OUT_DIV): TXOUT_DIV/RXOUT_DIV 设为 /1 (3'b011)
                    0: rom_data = {9'h088, 16'h0077, 16'h0011}; 
                    // 2) 0x011 (DATA_WIDTH): RX/TX 位宽设为 32-bit (3'b110)
                    1: rom_data = {9'h011, 16'h3838, 16'h3030}; 
                    //  5G 速率对应的 CDR 鉴相与环路滤波参数
                    2: rom_data = {9'h011, 16'h3838, 16'h2828}; 
                    default: rom_data = { {DRP_ADDR_WIDTH{1'b0}}, 32'd0 };
                endcase
            end
			
            default: begin
                total_entries = 0;
                rom_data      = { {DRP_ADDR_WIDTH{1'b0}}, 32'd0 };
            end
        endcase
    end

    // =========================================================================
    // 3. FSM 状态机实现 (读-改-写 + 遍历 + 复位)
    // =========================================================================
    localparam STATE_IDLE      = 3'd0;
    localparam STATE_READ_DRP  = 3'd1;
    localparam STATE_WAIT_READ = 3'd2;
    localparam STATE_WRITE_DRP = 3'd3;
    localparam STATE_WAIT_WR   = 3'd4;
    localparam STATE_GT_RESET  = 3'd5;
    localparam STATE_WAIT_DONE = 3'd6;

    reg [2:0]  state;
    reg [15:0] drp_rd_data;
    reg [15:0] timeout_cnt;

    // 计算修改后的新值：原值清零 MASK 位，然后或上目标 Value
    wire [15:0] drp_new_data = (drp_rd_data & ~current_mask) | (current_val & current_mask);

    always @(posedge clk) begin
        if (rst) begin
            state        <= STATE_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            drp_en       <= 1'b0;
            drp_we       <= 1'b0;
            drp_addr     <= {DRP_ADDR_WIDTH{1'b0}};
            drp_di       <= 16'd0;
            gt_soft_rst  <= 1'b0;
            rom_addr     <= 0;
            drp_rd_data  <= 16'd0;
            timeout_cnt  <= 16'd0;
        end else begin
            // 默认控制脉冲清零
            drp_en <= 1'b0;
            drp_we <= 1'b0;
            done   <= 1'b0;

            case (state)
                // -------------------------------------------------------------
                // 等待触发指令
                // -------------------------------------------------------------
                STATE_IDLE: begin
                    gt_soft_rst <= 1'b0;
                    rom_addr    <= 0;
                    if (start_cfg) begin
                        busy  <= 1'b1;
                        state <= STATE_READ_DRP;
                    end else begin
                        busy  <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // 步骤 1: 读取当前 ROM 指向的 DRP 寄存器
                // -------------------------------------------------------------
                STATE_READ_DRP: begin
                    drp_addr <= current_drp_addr;
                    drp_en   <= 1'b1;
                    drp_we   <= 1'b0; // 读操作
                    state    <= STATE_WAIT_READ;
                end

                // -------------------------------------------------------------
                // 等待 DRP 读数据返回
                // -------------------------------------------------------------
                STATE_WAIT_READ: begin
                    if (drp_rdy) begin
                        drp_rd_data <= drp_do;
                        state       <= STATE_WRITE_DRP;
                    end
                end

                // -------------------------------------------------------------
                // 步骤 2: 将掩码修改后的数据写回 DRP
                // -------------------------------------------------------------
                STATE_WRITE_DRP: begin
                    drp_addr <= current_drp_addr;
                    drp_en   <= 1'b1;
                    drp_we   <= 1'b1; // 写操作
                    drp_di   <= drp_new_data;
                    state    <= STATE_WAIT_WR;
                end

                // -------------------------------------------------------------
                // 等待 DRP 写完成，并判断是否继续遍历 ROM
                // -------------------------------------------------------------
                STATE_WAIT_WR: begin
                    if (drp_rdy) begin
                        if (rom_addr + 1'b1 < total_entries) begin
                            // 还有未配置的寄存器，取下一个地址
                            rom_addr <= rom_addr + 1'b1;
                            state    <= STATE_READ_DRP;
                        end else begin
                            // 所有 DRP 寄存器写入完毕，发起 GT 复位
                            state       <= STATE_GT_RESET;
                            timeout_cnt <= 16'd0;
                        end
                    end
                end

                // -------------------------------------------------------------
                // 步骤 3: 发起 GT 软复位
                // -------------------------------------------------------------
                STATE_GT_RESET: begin
                    gt_soft_rst <= 1'b1;
                    timeout_cnt <= timeout_cnt + 1'b1;
                    // 持续拉高软复位约 64 个时钟周期
                    if (timeout_cnt >= 16'd64) begin
                        gt_soft_rst <= 1'b0;
                        timeout_cnt <= 16'd0;
                        state       <= STATE_WAIT_DONE;
                    end
                end

                // -------------------------------------------------------------
                // 步骤 4: 等待 GT 硬件复位完成握手 (带超时保护)
                // -------------------------------------------------------------
                STATE_WAIT_DONE: begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                    
                    // TX 和 RX 都复位成功
                    if (gt_txresetdone && gt_rxresetdone) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= STATE_IDLE;
                    end 
                    // 防止复位失败死锁 (如超时 50,000 个周期强制退出)
                    else if (timeout_cnt > 16'd50000) begin
                        done  <= 1'b1; // 也可单独输出 error 信号
                        busy  <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule