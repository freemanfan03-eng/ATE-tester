`timescale 1ns/1ps

// ============================================================================
// Module: Global_timing_scheduler
// Description: Master Timing Base Engine for ATE Architecture.
//              Generates global T0 pulse and a 48-bit UI timebase counter
//              mapped cleanly into a single DSP48 hard block.
// ============================================================================

module Global_timing_scheduler (
    input  wire        clk,            // 低抖动主时钟 (如 312.5MHz txuserclk2)
    input  wire        rst_n,          // 外部全局复位 (异步低有效)
    input  wire        trig_start,     // 软件/Sequencer 启动命令

    // 分发给各个 Pin Engine 的全局控制线
    output reg         global_t0=0,      // 全局 T0 硬件对齐单脉冲
	output reg         global_t1=0,      // 
	output reg         global_t2=0,      // 
    
    (* use_dsp = "yes" *)
    output reg [47:0]  global_ui_cnt   // 全局时间轴累加计数器 (绑定 DSP48)
);

    // ------------------------------------------------------------------------
    // 1. 复位同步桥 (Reset Synchronizer)
    //    将外部异步 rst_n 转为时钟域内的同步高有效复位 (srst)。
    //    这是让综合工具将 48-bit 计数器塞入 DSP48 的核心关键技巧。
    // ------------------------------------------------------------------------
    reg [1:0] rst_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], 1'b0};
    end
    wire srst = rst_sync[1]; // 同步后的内部高有效复位

    // ------------------------------------------------------------------------
    // 2. 启动脉冲检测逻辑 (捕获 trig_start 上升沿，产生单周期 T0)
    // ------------------------------------------------------------------------
    reg trig_start_d;
	reg trig_pulse;
	reg status;
    always @(posedge clk) begin
        if (srst) begin
            trig_start_d <= 1'b0;
			global_t0    <= 1'b0;
			global_t1    <= 1'b0;
			global_t1    <= 1'b0;
			
        end else begin
            trig_start_d <= trig_start;
            trig_pulse    <= trig_start && !trig_start_d; // 仅拉高 1 个 Clock
			
			
			
			if(global_ui_cnt == 5)global_t1 <= 1'b1;
			else global_t1 <= 1'b0;
			
			if(global_ui_cnt == 20)global_t2 <= 1'b1;
			else global_t2 <= 1'b0;
			
        end
    end

    // ------------------------------------------------------------------------
    // 3. 48-bit 全局时间轴计数器 (全同步 P-Register 累加结构)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (srst) begin
            global_ui_cnt <= 48'd0;     // T0 触发或系统复位时归零
			status 		 <= 1'b0;
        end else begin
	
			case(status)
			 0:if(trig_pulse)begin 
					status <= 1'b1;
					global_t0  <= 1'b1;
			 end 
			 1:begin
					
					if(trig_pulse)begin
						status <= 1'b0;
						global_t0  <= 1'b1;
					end 
					else begin
						global_t0  <= 1'b0;
						global_ui_cnt <= global_ui_cnt + 48'd1; // DSP 内部 P <= P + 1 自由累加
					end 
					
			 end 
			endcase 
			
			
            
        end
    end

endmodule