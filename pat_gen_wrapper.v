// 5. 多通道与宽总线自适应包装器模块 (Pattern Engine Wrapper - 标准直连版)
module pat_gen_wrapper #(
	parameter integer DATA_WIDTH = 32,
    parameter integer NUM_CHANNELS = 8,      // 总体并行通道数
    parameter integer MEM_WIDTH    = 32,     // 存储器单次读取的数据位宽
    parameter integer EDGE_WIDTH   = 16,
    parameter integer PERIOD_WIDTH = 24,
	parameter integer PAT_ACT_GROUNP  					= 2
)(
    input wire                     clk,
    input wire                     rst_n,
    input wire                     trigger_sync,   
    
    // 宽总线存储器接口
    input wire                     mem_data_vld,   
    input wire [MEM_WIDTH-1:0]     mem_data_in,    
    
    // 周期与配置
    input wire [PERIOD_WIDTH-1:0]  period_ui_in,
	input  wire [32*PAT_ACT_GROUNP-1:0]pattern_act_cfg,
    input wire [3:0]               pattern_index,  
	input wire [2:0]               data_src_sel,
	
    // 多通道边沿输入总线
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_0_in,  
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_1_in,
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_2_in,
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_3_in,
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_4_in,
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_5_in,
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_r0_in,
    input wire [NUM_CHANNELS*EDGE_WIDTH-1:0] edge_r1_in,
    
    // 多通道串行接收比对数据输入
    input wire [NUM_CHANNELS*DATA_WIDTH-1:0] rx_cmp_h_dat_arr,              
    input wire [NUM_CHANNELS*DATA_WIDTH-1:0] rx_cmp_l_dat_arr,         

    // 多通道并行输出
    output wire [NUM_CHANNELS*DATA_WIDTH-1:0] dat_parallel_arr,        
    output wire [NUM_CHANNELS*DATA_WIDTH-1:0] rcv_parallel_arr,  
	output wire [NUM_CHANNELS*DATA_WIDTH-1:0] pass_fail_arr,

	
    output wire [NUM_CHANNELS-1:0] test_fail_arr,      
    output wire                    next_mem_req, 
	output wire [NUM_CHANNELS-1:0] period_ends,	
    output wire [NUM_CHANNELS-1:0] tx_ui_t0

);

	wire [DATA_WIDTH-1:0] dat_parallel[NUM_CHANNELS-1:0];
    wire [DATA_WIDTH-1:0] rcv_parallel[NUM_CHANNELS-1:0];
  // =========================================================================
    // 多通道 Pattern 产生器例化 (遵循 Verilog-2001 generate 规范)
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : gen_channels
            pat_gen #(
                .DATA_WIDTH(DATA_WIDTH),
                .EDGE_WIDTH(EDGE_WIDTH),
                .PERIOD_WIDTH(PERIOD_WIDTH),
                .PAT_ACT_GROUNP(PAT_ACT_GROUNP)
            ) u_pat_gen_inst (
                .clk(clk),
                .rst_n(rst_n),
                
                // 全局控制与 Pattern 动态输入数据
                .trigger_sync(trigger_sync),
                .period_ui_in(period_ui_in),
               // .pattern_act_cfg(pattern_act_cfg[i*32 +: 32]),

                .data_src_sel(data_src_sel),     
                .pattern_index(pattern_index),      
                  
                // 边沿时间戳
                .act_edge_0_ui (edge_0_in  [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .act_edge_1_ui (edge_1_in  [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .act_edge_2_ui (edge_2_in  [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .act_edge_3_ui (edge_3_in  [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .act_edge_4_ui (edge_4_in  [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .act_edge_5_ui (edge_5_in  [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .cmp_edge_r0_ui(edge_r0_in [i*EDGE_WIDTH +: EDGE_WIDTH]),
                .cmp_edge_r1_ui(edge_r1_in [i*EDGE_WIDTH +: EDGE_WIDTH]),

                // 接口 1：发送与流控 (正确的按通道切片)
                .next_vector_req(tx_ui_t0[i]),
           
                .drv_parallel_data(dat_parallel_arr[i*DATA_WIDTH +: DATA_WIDTH]),
                .rcv_parallel_data(rcv_parallel_arr[i*DATA_WIDTH +: DATA_WIDTH]),
                
                // 接口 2：接收来自 GT 硬件的采样数据
                .cmp_h_in(rx_cmp_h_dat_arr[i*DATA_WIDTH +: DATA_WIDTH]),
                .cmp_l_in(rx_cmp_l_dat_arr[i*DATA_WIDTH +: DATA_WIDTH]),
                
                // 接口 3：比对结果输出 (正确连接到顶层总线与标志)
                .pass_fail_vector(pass_fail_arr[i*DATA_WIDTH +: DATA_WIDTH]),
                .channel_fail_flag(test_fail_arr[i])
            );
        end
    endgenerate

endmodule