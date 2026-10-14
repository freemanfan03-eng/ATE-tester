module pattern_sequence #(
    // --- gt_multilane_wrapper 相关参数 ---
	parameter 		  GT_ENABLE					=	"FALSE",
    parameter integer GT_DATA_WIDTH             = 32,
    parameter         EXAMPLE_SIM_GTRESET_SPEEDUP = "TRUE",
    parameter real    STABLE_CLOCK_PERIOD         = 8.0,
    
    // --- pattern_engine_wrapper 相关参数 ---
    parameter integer NUM_CHANNELS                      = 2,     // 匹配 2 个高速收发通道
    parameter integer MEM_WIDTH                         = 32,
    parameter integer EDGE_WIDTH                        = 16,
    parameter integer PERIOD_WIDTH                      = 24,
	parameter integer PAT_ACT_GROUNP  					= 2
)(


	// =========================================================================
    // --- pattern_engine_wrapper 引入的顶层控制与配置接口 ---
    // =========================================================================
   
    input  wire                                 trigger_sync,
    
    // 宽总线存储器接口
    input  wire                                 mem_data_vld,
    input  wire [MEM_WIDTH-1:0]                 mem_data_in,
    
    // 周期与配置
    input  wire [PERIOD_WIDTH-1:0]              period_ui_in,
    input  wire [3:0]                           pattern_index,
	input  wire [32*PAT_ACT_GROUNP-1:0]			pattern_act_cfg,
    input  wire [2:0]                           data_src_sel,
    
    // 多通道边沿输入总线
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_0_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_1_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_2_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_3_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_4_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_5_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_r0_in,
    input  wire [NUM_CHANNELS*EDGE_WIDTH-1:0]   edge_r1_in,
    
    output wire [NUM_CHANNELS-1:0]              test_fail_arr,
    output wire                                 next_mem_req,
    output wire [NUM_CHANNELS-1:0]              period_ends,
    output wire [NUM_CHANNELS-1:0]              tx_ui_t0,
    // --- 顶层系统时钟与复位 ---
    input  wire                                 sysclk_in,
    input  wire                                 soft_reset_i,
    
    // --- 差分参考时钟引脚 ---
    input  wire                                 Q0_CLK0_GTREFCLK_PAD_N_IN,
    input  wire                                 Q0_CLK0_GTREFCLK_PAD_P_IN,

	input wire [8:0]  							gt0_drpaddr_i,
    input wire [15:0] 							gt0_drpdi_i,
    output wire [15:0] 							gt0_drpdo_o,
    input wire        							gt0_drpen_i,
    output wire        							gt0_drprdy_o,
    input wire        							gt0_drpwe_i,

    
    // --- 高速串行差分收发物理引脚 (2通道) ---
    input  wire [1:0]                           RXP_IN,
    input  wire [1:0]                           RXN_IN,
    output wire [1:0]                           TXP_OUT,
    output wire [1:0]                           TXN_OUT,
	
	// 高速收发器恢复出来的时钟
    output wire        							gt0_txusrclk2_out,
    output wire        							gt0_rxusrclk2_out,
    output wire        							gt1_txusrclk2_out,
    output wire        							gt1_rxusrclk2_out,
    output wire  								gt0_tx_ready_out, 
    output wire 								gt1_tx_ready_out     
   
);


    // =========================================================================
    // 内部信号定义
    // =========================================================================
    

    // 多通道串行接收比对数据输入 (外部回环或接收解析后传入)
	//wire [GT_DATA_WIDTH*NUM_CHANNELS-1:0]  			gt0_rxdata_out ;
   // wire [GT_DATA_WIDTH*NUM_CHANNELS-1:0]   		gt1_rxdata_out ;
    wire [GT_DATA_WIDTH*NUM_CHANNELS-1:0]           rx_cmp_h_dat_arr ;
    wire [GT_DATA_WIDTH*NUM_CHANNELS-1:0]           rx_cmp_l_dat_arr ;
	
    wire [GT_DATA_WIDTH*NUM_CHANNELS-1:0] 			dat_parallel_arr;        
    wire [GT_DATA_WIDTH*NUM_CHANNELS-1:0] 			rcv_parallel_arr;  

	wire txusrclk2 = gt0_txusrclk2_out ;
	wire rst_n = gt0_tx_ready_out;
	
	wire trigger_sync_cdc;
	xpm_cdc_pulse #(
		.DEST_SYNC_FF  (2),
		.INIT_SYNC_FF  (0),    // 仿真时给内部寄存器赋初值
		.REG_OUTPUT    (1),
		.RST_USED      (0),
		.SIM_ASSERT_CHK(1)     // 仿真阶段建议打开,能提示脉冲间隔等问题
	) u_trig_pulse (
		.dest_pulse(trigger_sync_cdc),
		.dest_clk  (sysclk_in),
		//.dest_clk  (txusrclk2),
		.dest_rst  (soft_reset_i),
		.src_clk   (sysclk_in),
		.src_pulse (trigger_sync),
		.src_rst   (soft_reset_i)
	);
   // End of xpm_cdc_single_inst instantiation
   
   
 // =========================================================================
    // 1. 例化 pattern_engine_wrapper (图形引擎 / 产生与比对核心)
    // =========================================================================
    pat_gen_wrapper #(
		.DATA_WIDTH				 	 (GT_DATA_WIDTH),
        .NUM_CHANNELS                (NUM_CHANNELS),
        .MEM_WIDTH                   (MEM_WIDTH),
        .EDGE_WIDTH                  (EDGE_WIDTH),
        .PERIOD_WIDTH                (PERIOD_WIDTH)
    ) u_pat_gen_wrapper (
       // .clk                         (txusrclk2),     //txusrclk2可按需使用 gt0_txusrclk2_i 代替
		.clk                         (sysclk_in),     //txusrclk2可按需使用 gt0_txusrclk2_i 代替
        .rst_n                       (soft_reset_i),
        .trigger_sync                (trigger_sync_cdc),
        
        .mem_data_vld                (mem_data_vld),
        .mem_data_in                 (mem_data_in),
        
        .period_ui_in                (period_ui_in),
        .pattern_index               (pattern_index),
		.pattern_act_cfg			 (pattern_act_cfg),
        .data_src_sel                (data_src_sel),
		
		
        
        .edge_0_in                   (edge_0_in),
        .edge_1_in                   (edge_1_in),
        .edge_2_in                   (edge_2_in),
        .edge_3_in                   (edge_3_in),
        .edge_4_in                   (edge_4_in),
        .edge_5_in                   (edge_5_in),
        .edge_r0_in                  (edge_r0_in),
        .edge_r1_in                  (edge_r1_in),
        
        .rx_cmp_h_dat_arr            (rx_cmp_h_dat_arr),
        .rx_cmp_l_dat_arr            (rx_cmp_l_dat_arr),
        
        .dat_parallel_arr			 (dat_parallel_arr),
		.rcv_parallel_arr			 (rcv_parallel_arr),
        .test_fail_arr               (test_fail_arr),
        .next_mem_req                (next_mem_req),
        .tx_ui_t0                    (tx_ui_t0)
       
    );
	
    // =========================================================================
    // 2. 例化 gt_multilane_wrapper (2通道高速串行收发器)
    // =========================================================================
	generate
		if (GT_ENABLE == "TRUE") begin : gt_transceiver
	
			gt_multilane_wrapper #(
				.GT_DATA_WIDTH               (GT_DATA_WIDTH),
				.EXAMPLE_SIM_GTRESET_SPEEDUP (EXAMPLE_SIM_GTRESET_SPEEDUP),
				.STABLE_CLOCK_PERIOD         (STABLE_CLOCK_PERIOD)
			) u_gt_multilane_wrapper (
				.sysclk_in                   (sysclk_in),
				.soft_reset_i                (!soft_reset_i),
				
				.Q0_CLK0_GTREFCLK_PAD_N_IN   (Q0_CLK0_GTREFCLK_PAD_N_IN),
				.Q0_CLK0_GTREFCLK_PAD_P_IN   (Q0_CLK0_GTREFCLK_PAD_P_IN),

				//
				.gtx_drpaddr_i				(),
				.gtx_drpdi_i				(),
				.gtx_drpdo_o				(gt0_drpdo_o),
				.gtx_drpen_i				(),
				.gtx_drprdy_o				(gt0_drprdy_o),
				.gtx_drpwe_i				(),

				//
				.RXP_IN                      (RXP_IN),
				.RXN_IN                      (RXN_IN),
				.TXP_OUT                     (TXP_OUT),
				.TXN_OUT                     (TXN_OUT),
				
				// 将 pattern_engine 生成的并行数据对应接到 GT 的 TX 输入
				.gt0_txdata_in               (dat_parallel_arr   [0 * GT_DATA_WIDTH +: GT_DATA_WIDTH]), //Pattern data (tx)
				.gt0_rxdata_out              (rx_cmp_h_dat_arr   [0 * GT_DATA_WIDTH +: GT_DATA_WIDTH]), // data from  gt pattern Sequence (rx )
				//
				.gt1_txdata_in               (rcv_parallel_arr   [0 * GT_DATA_WIDTH +: GT_DATA_WIDTH]),
				.gt1_rxdata_out              (rx_cmp_l_dat_arr   [0 * GT_DATA_WIDTH +: GT_DATA_WIDTH]),
				
				.gt0_txusrclk2_out           (gt0_txusrclk2_out),
				.gt0_rxusrclk2_out           (gt0_rxusrclk2_out),
				.gt1_txusrclk2_out           (gt1_txusrclk2_out),
				.gt1_rxusrclk2_out           (gt1_rxusrclk2_out),
				
				.gt0_tx_ready_out            (gt0_tx_ready_out),
				.gt1_tx_ready_out            (gt1_tx_ready_out)
			);
		
		end 
   endgenerate
   

endmodule